#!/usr/bin/env python3
"""measure exploratory gif encoders on one synthetic png sequence."""

import argparse
import hashlib
import json
import math
import os
import platform
import re
import shutil
import signal
import statistics
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parent
PRIMARY_MATRIX_CANDIDATES = ("gifski", "magick", "magick-unoptimized", "imageio", "imageio-gifsicle")
CANDIDATES = (*PRIMARY_MATRIX_CANDIDATES, "imageio-app")
RSS_PATTERN = re.compile(r"(\d+)\s+maximum resident set size")
CPU_PATTERN = re.compile(r"([\d.]+)\s+real\s+([\d.]+)\s+user\s+([\d.]+)\s+sys")
POSIX_CPU_PATTERN = re.compile(r"real\s+([\d.]+)\s+user\s+([\d.]+)\s+sys\s+([\d.]+)")


def capture(command):
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=20, check=False)
        return {"command": command, "exit_code": result.returncode, "stdout": result.stdout.strip(), "stderr": result.stderr.strip()}
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"command": command, "error": str(error)}


def digest(path):
    checksum = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            checksum.update(block)
    return checksum.hexdigest()


def fixture_digest(frames):
    checksum = hashlib.sha256()
    for frame in frames:
        checksum.update(frame.name.encode("utf-8"))
        checksum.update(b"\0")
        checksum.update(bytes.fromhex(digest(frame)))
    return checksum.hexdigest()


def tree_bytes(path):
    total = 0
    for root, _, files in os.walk(path):
        for name in files:
            try:
                total += (Path(root) / name).stat().st_size
            except FileNotFoundError:
                pass
    return total


def process_tree_rss_bytes(ps_output, root_pid):
    processes = {}
    for line in ps_output.splitlines():
        fields = line.split()
        if len(fields) != 3:
            continue
        try:
            pid, parent_pid, rss_kib = (int(field) for field in fields)
        except ValueError:
            continue
        processes[pid] = (parent_pid, rss_kib)
    if root_pid not in processes:
        return None

    tree_pids = {root_pid}
    changed = True
    while changed:
        changed = False
        for pid, (parent_pid, _) in processes.items():
            if parent_pid in tree_pids and pid not in tree_pids:
                tree_pids.add(pid)
                changed = True
    return sum(processes[pid][1] for pid in tree_pids) * 1024


def cpu_seconds(stderr, use_system_time, use_posix_time):
    if use_system_time:
        match = CPU_PATTERN.search(stderr)
        return (float(match.group(2)), float(match.group(3))) if match else (None, None)
    if use_posix_time:
        match = POSIX_CPU_PATTERN.search(stderr)
        return (float(match.group(2)), float(match.group(3))) if match else (None, None)
    return None, None


def gif_metadata(path):
    data = path.read_bytes()
    if len(data) < 14 or data[:6] not in (b"GIF87a", b"GIF89a"):
        raise ValueError("invalid GIF header")
    width = int.from_bytes(data[6:8], "little")
    height = int.from_bytes(data[8:10], "little")
    if width == 0 or height == 0:
        raise ValueError("invalid GIF dimensions")
    position = 13
    if data[10] & 0x80:
        position += 3 * (1 << ((data[10] & 7) + 1))
    delays = []
    pending_delay = 0
    loop_count = None

    def subblocks(at):
        chunks = []
        while True:
            if at >= len(data):
                raise ValueError("truncated GIF sub-block")
            size = data[at]
            at += 1
            if size == 0:
                return at, chunks
            if at + size > len(data):
                raise ValueError("truncated GIF sub-block data")
            chunks.append(data[at : at + size])
            at += size

    while position < len(data):
        marker = data[position]
        position += 1
        if marker == 0x3B:
            return {
                "width": width,
                "height": height,
                "frame_count": len(delays),
                "duration_seconds": round(sum(delays) / 100, 4),
                "frame_delays_centiseconds": delays,
                "loop_count": loop_count,
                "bytes": len(data),
            }
        if marker == 0x21:
            if position >= len(data):
                raise ValueError("truncated GIF extension")
            label = data[position]
            position += 1
            if label == 0xF9:
                if position + 6 > len(data) or data[position] != 4:
                    raise ValueError("invalid GIF graphics control extension")
                pending_delay = int.from_bytes(data[position + 2 : position + 4], "little")
                position += 6
            elif label == 0xFF:
                if position >= len(data):
                    raise ValueError("truncated GIF application extension")
                size = data[position]
                position += 1
                identifier = data[position : position + size]
                position += size
                position, blocks = subblocks(position)
                if identifier.startswith((b"NETSCAPE", b"ANIMEXTS")):
                    for block in blocks:
                        if len(block) >= 3 and block[0] == 1:
                            loop_count = int.from_bytes(block[1:3], "little")
                            break
            else:
                if label == 0x01:
                    if position >= len(data):
                        raise ValueError("truncated GIF text extension")
                    position += 1 + data[position]
                position, _ = subblocks(position)
        elif marker == 0x2C:
            if position + 9 > len(data):
                raise ValueError("truncated GIF image descriptor")
            packed = data[position + 8]
            position += 9
            if packed & 0x80:
                position += 3 * (1 << ((packed & 7) + 1))
            position += 1
            position, _ = subblocks(position)
            delays.append(pending_delay)
            pending_delay = 0
        else:
            raise ValueError(f"invalid GIF block marker: {marker:#x}")
    raise ValueError("missing GIF trailer")


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[max(0, math.ceil(fraction * len(ordered)) - 1)]


def candidate_order(candidates, round_index):
    """Alternate path order between successive cold and warm rounds."""
    ordered = list(candidates)
    return ordered if round_index % 2 == 0 else list(reversed(ordered))


def summary_sample(sample):
    """Keep comparable per-run metrics in the compact report."""
    gif = sample.get("gif", {})
    return {
        "run": sample["run"],
        "round": sample.get("round"),
        "run_state": "cold_first_invocation" if sample["run"] == "cold" else "warm",
        "status": sample["status"],
        "elapsed_seconds": sample["elapsed_seconds"],
        "component_elapsed_seconds": sample.get("component_elapsed_seconds"),
        "cpu_user_seconds": sample["cpu_user_seconds"],
        "cpu_system_seconds": sample["cpu_system_seconds"],
        "bytes": sample.get("output_bytes"),
        "output_sha256": sample.get("output_sha256"),
        "retained_output": sample.get("retained_output", False),
        "retained_output_path": sample.get("retained_output_path"),
        "width": gif.get("width"),
        "height": gif.get("height"),
        "frame_count": gif.get("frame_count"),
        "duration_seconds": gif.get("duration_seconds"),
        "frame_delays_centiseconds": gif.get("frame_delays_centiseconds"),
        "loop_count": gif.get("loop_count"),
        "peak_resident_bytes_reported": sample["peak_resident_bytes_reported"],
        "memory_measurement": sample.get("memory_measurement", "unavailable"),
        "peak_workspace_bytes_sampled": sample["peak_workspace_bytes_sampled"],
        "stages": [
            {
                "stage": stage.get("stage"),
                "elapsed_seconds": stage.get("elapsed_seconds"),
                "cpu_user_seconds": stage.get("cpu_user_seconds"),
                "cpu_system_seconds": stage.get("cpu_system_seconds"),
                "peak_resident_bytes_reported": stage.get("peak_resident_bytes_reported"),
                "peak_workspace_bytes_sampled": stage.get("peak_workspace_bytes_sampled"),
            }
            for stage in sample.get("stage_results", [])
        ],
    }


def expected_frame_delays(fps, frame_count):
    """Return centisecond delays from rounded cumulative frame boundaries."""
    def boundary(index):
        return math.floor(index * 100 / fps + 0.5)

    return [boundary(index + 1) - boundary(index) for index in range(frame_count)]


def diffusion_amount(value):
    """Parse ImageMagick's numeric diffusion amount as a percentage."""
    try:
        amount = int(value)
    except (TypeError, ValueError) as error:
        raise argparse.ArgumentTypeError("diffusion amount must be an integer from 0 to 100") from error
    if (isinstance(value, float) and not value.is_integer()) or not 0 <= amount <= 100:
        raise argparse.ArgumentTypeError("diffusion amount must be from 0 to 100")
    return amount


def environment():
    return {
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "platform": platform.platform(),
        "machine": platform.machine(),
        "mac_model": capture(["sysctl", "-n", "hw.model"]),
        "chip": capture(["sysctl", "-n", "machdep.cpu.brand_string"]),
        "memory_bytes": capture(["sysctl", "-n", "hw.memsize"]),
        "os_version": capture(["sw_vers"]),
        "power_settings": capture(["pmset", "-g", "custom"]),
        "thermal_status": capture(["pmset", "-g", "therm"]),
        "xcode": capture(["xcodebuild", "-version"]),
        "git_commit": capture(["git", "rev-parse", "HEAD"]),
        "thermal_state": "see pmset -g therm output; sample start and end status manually",
    }


def discover(output, imageio_app_binary=None):
    found = {}
    for name in ("gifski", "magick", "gifsicle"):
        executable = shutil.which(name)
        found[name] = {"available": executable is not None}
        if executable:
            path = Path(executable).resolve()
            found[name].update({"path": str(path), "sha256": digest(path), "version": capture([str(path), "--version"]), "architectures": capture(["lipo", "-archs", str(path)]), "linked_libraries": capture(["otool", "-L", str(path)])})
    swiftc = shutil.which("xcrun")
    helper = ROOT / "imageio_encode.swift"
    found["imageio"] = {"available": False, "source": str(helper), "source_sha256": digest(helper)}
    if swiftc:
        tool = output / "tools" / "imageio_encode"
        tool.parent.mkdir()
        compilation = capture([swiftc, "swiftc", "-module-cache-path", str(output / "tools" / "module-cache"), str(helper), "-o", str(tool)])
        found["imageio"]["compile"] = compilation
        if compilation.get("exit_code") == 0 and tool.exists():
            found["imageio"].update({"available": True, "path": str(tool), "sha256": digest(tool), "architectures": capture(["lipo", "-archs", str(tool)]), "linked_libraries": capture(["otool", "-L", str(tool)])})
    else:
        found["imageio"]["reason"] = "xcrun unavailable"
    app_sources = [
        ROOT / ".." / "Sources" / "Recording" / "SessionWorkspaceStore.swift",
        ROOT / ".." / "Sources" / "Encoding" / "GIFEditModel.swift",
        ROOT / ".." / "Sources" / "Encoding" / "OriginalGIFEncoder.swift",
        ROOT / "imageio_app_encode.swift",
    ]
    found["imageio-app"] = {
        "available": False,
        "sources": [str(path.resolve()) for path in app_sources],
        "source_sha256": {path.name: digest(path) for path in app_sources},
    }
    if imageio_app_binary is not None:
        binary = imageio_app_binary.resolve()
        if binary.is_file():
            found["imageio-app"].update({"available": True, "path": str(binary), "prebuilt_binary": True, "compile_elapsed_seconds": 0.0, "sha256": digest(binary), "architectures": capture(["lipo", "-archs", str(binary)]), "linked_libraries": capture(["otool", "-L", str(binary)])})
        else:
            found["imageio-app"]["reason"] = f"missing prebuilt binary: {binary}"
    elif swiftc:
        tool = output / "tools" / "imageio_app_encode"
        started = time.perf_counter()
        compilation = capture([
            swiftc,
            "swiftc",
            "-module-cache-path",
            str(output / "tools" / "module-cache-app"),
            *map(str, app_sources),
            "-o",
            str(tool),
        ])
        found["imageio-app"]["compile_elapsed_seconds"] = time.perf_counter() - started
        found["imageio-app"]["prebuilt_binary"] = False
        found["imageio-app"]["compile"] = compilation
        if compilation.get("exit_code") == 0 and tool.exists():
            found["imageio-app"].update({"available": True, "path": str(tool), "sha256": digest(tool), "architectures": capture(["lipo", "-archs", str(tool)]), "linked_libraries": capture(["otool", "-L", str(tool)])})
    else:
        found["imageio-app"]["reason"] = "xcrun unavailable"
    return found


def path_availability(name, tools):
    required = {
        "gifski": ("gifski",),
        "magick": ("magick",),
        "magick-unoptimized": ("magick",),
        "imageio": ("imageio",),
        "imageio-app": ("imageio-app",),
        "imageio-gifsicle": ("imageio", "gifsicle"),
    }[name]
    required = tuple(required) if name == "imageio-app" else (*required, "imageio-app")
    missing = [tool for tool in required if not tools.get(tool, {}).get("available", "path" in tools.get(tool, {}))]
    return {"available": not missing, "required_tools": list(required), "missing_tools": missing, "reason": f"missing: {', '.join(missing)}" if missing else None}


def command_for(name, tools, fps, frames, output, magick_diffusion_amount=100):
    magick_diffusion_amount = diffusion_amount(magick_diffusion_amount)
    binary = tools["magick"]["path"] if name == "magick-unoptimized" else tools[name]["path"]
    if name == "gifski":
        return [binary, "--fps", str(fps), "--quality", "90", "--repeat", "0", "--no-sort", "-o", str(output), *map(str, frames)]
    if name in ("magick", "magick-unoptimized"):
        timed_frames = []
        for frame, delay in zip(frames, expected_frame_delays(fps, len(frames))):
            timed_frames.extend(["-delay", f"{delay}x100", str(frame)])
        command = [binary, *timed_frames, "-dither", "FloydSteinberg", "-define", f"dither:diffusion-amount={magick_diffusion_amount}%", "-colors", "256"]
        if name == "magick":
            command.extend(["-layers", "Optimize"])
        return [*command, "-loop", "0", str(output)]
    return [binary, str(fps), str(output), *map(str, frames)]


def command_sequence_for(name, tools, fps, frames, output, work, magick_diffusion_amount=100):
    if name != "imageio-gifsicle":
        stages = [{"stage": name, "command": command_for(name, tools, fps, frames, output, magick_diffusion_amount)}]
    else:
        intermediate = work / "imageio-input.gif"
        stages = [
            {
            "stage": "imageio",
            "command": command_for("imageio", tools, fps, frames, intermediate),
            },
            {
                "stage": "gifsicle",
                "command": [
                    tools["gifsicle"]["path"],
                    "--optimize=3",
                    "--loopcount=0",
                    "--output",
                    str(output),
                    str(intermediate),
                ],
            },
        ]
    # the app candidate validates its own output through GIFMetadataInspector before
    # returning. other paths run that same per-frame ImageIO metadata inspection here.
    if name != "imageio-app" and tools.get("imageio-app", {}).get("path"):
        stages.append(
            {
                "stage": "imageio-metadata-validation",
                "command": [tools["imageio-app"]["path"], "--validate", str(output)],
            }
        )
    return stages


def run_command(command, work, timeout_seconds, use_system_time, use_posix_time=False):
    peak_bytes = 0
    peak_rss_bytes = None
    done = threading.Event()
    wrapped = ["/usr/bin/time", "-l", *command] if use_system_time else ["/usr/bin/time", "-p", *command] if use_posix_time else command
    started = time.perf_counter()
    process = subprocess.Popen(wrapped, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)

    def monitor():
        nonlocal peak_bytes, peak_rss_bytes
        while not done.wait(0.02):
            peak_bytes = max(peak_bytes, tree_bytes(work))
            if not use_system_time:
                if use_posix_time:
                    sample = capture(["ps", "-axo", "pid=,ppid=,rss="])
                    sample_rss = process_tree_rss_bytes(sample.get("stdout", ""), process.pid) if sample.get("exit_code") == 0 else None
                else:
                    sample = capture(["ps", "-o", "rss=", "-p", str(process.pid)])
                    sample_rss = int(sample["stdout"].strip()) * 1024 if sample.get("exit_code") == 0 and sample["stdout"].strip().isdigit() else None
                if sample_rss is not None:
                    peak_rss_bytes = max(peak_rss_bytes or 0, sample_rss)

    thread = threading.Thread(target=monitor, daemon=True)
    thread.start()
    timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        timed_out = True
        os.killpg(process.pid, signal.SIGTERM)
        try:
            stdout, stderr = process.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate()
    finally:
        elapsed = time.perf_counter() - started
        done.set()
        thread.join()
        peak_bytes = max(peak_bytes, tree_bytes(work))
    match = RSS_PATTERN.search(stderr)
    cpu_user_seconds, cpu_system_seconds = cpu_seconds(stderr, use_system_time, use_posix_time)
    return {"command": command, "elapsed_seconds": elapsed, "cpu_user_seconds": cpu_user_seconds, "cpu_system_seconds": cpu_system_seconds, "exit_code": process.returncode, "timed_out": timed_out, "peak_workspace_bytes_sampled": peak_bytes, "peak_resident_bytes_reported": int(match.group(1)) if match else peak_rss_bytes, "memory_measurement": "system_time" if match else "sampled_ps" if peak_rss_bytes is not None else "unavailable", "stdout": stdout[-16000:], "stderr": stderr[-16000:]}


def run_one(name, tools, manifest, frames, output, label, timeout_seconds, use_system_time, magick_diffusion_amount=100, retained_hashes=None, use_posix_time=False):
    fps = manifest["fps"]
    total_started = time.perf_counter()
    work = output / "work" / f"{name}-{label}"
    work.mkdir(parents=True)
    temporary_gif = work / "output.gif"
    commands = command_sequence_for(name, tools, fps, frames, temporary_gif, work, magick_diffusion_amount)
    try:
        stage_results = []
        deadline = time.monotonic() + timeout_seconds
        for stage in commands:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                stage_result = {
                    "command": stage["command"],
                    "elapsed_seconds": 0,
                    "cpu_user_seconds": None,
                    "cpu_system_seconds": None,
                    "exit_code": None,
                    "timed_out": True,
                    "peak_workspace_bytes_sampled": tree_bytes(work),
                    "peak_resident_bytes_reported": None,
                    "memory_measurement": "unavailable",
                    "stdout": "",
                    "stderr": "path timeout expired before this stage started",
                }
            else:
                stage_result = run_command(stage["command"], work, remaining, use_system_time, use_posix_time)
            stage_result["stage"] = stage["stage"]
            stage_results.append(stage_result)
            if stage_result["exit_code"] != 0 or stage_result["timed_out"]:
                break
        result = {
            "command": commands[0]["command"],
            "commands": [stage["command"] for stage in commands],
            "stage_results": stage_results,
            "magick_diffusion_amount_percent": magick_diffusion_amount if name in ("magick", "magick-unoptimized") else None,
            "elapsed_seconds": None,
            "component_elapsed_seconds": sum(stage["elapsed_seconds"] for stage in stage_results),
            "cpu_user_seconds": sum((stage["cpu_user_seconds"] or 0) for stage in stage_results) if any(stage["cpu_user_seconds"] is not None for stage in stage_results) else None,
            "cpu_system_seconds": sum((stage["cpu_system_seconds"] or 0) for stage in stage_results) if any(stage["cpu_system_seconds"] is not None for stage in stage_results) else None,
            "exit_code": stage_results[-1]["exit_code"],
            "timed_out": any(stage["timed_out"] for stage in stage_results),
            "peak_workspace_bytes_sampled": max(stage["peak_workspace_bytes_sampled"] for stage in stage_results),
            "peak_resident_bytes_reported": max((stage["peak_resident_bytes_reported"] for stage in stage_results if stage["peak_resident_bytes_reported"] is not None), default=None),
            "memory_measurement": "system_time" if all(stage["memory_measurement"] == "system_time" for stage in stage_results) else "sampled_ps" if any(stage["peak_resident_bytes_reported"] is not None for stage in stage_results) else "unavailable",
            "stdout": "\n".join(f"[{stage['stage']}] {stage['stdout']}" for stage in stage_results),
            "stderr": "\n".join(f"[{stage['stage']}] {stage['stderr']}" for stage in stage_results),
        }
        if result["exit_code"] == 0 and not result["timed_out"] and temporary_gif.exists():
            try:
                metadata = gif_metadata(temporary_gif)
                if metadata["frame_count"] == 0:
                    raise ValueError("GIF has no frames")
                if metadata["frame_count"] != len(frames):
                    raise ValueError(f"GIF frame count {metadata['frame_count']} differs from fixture count {len(frames)}")
                if metadata["width"] != manifest["width"] or metadata["height"] != manifest["height"]:
                    raise ValueError(
                        f"GIF dimensions {metadata['width']}x{metadata['height']} differ from fixture "
                        f"dimensions {manifest['width']}x{manifest['height']}"
                    )
                if metadata["loop_count"] != 0:
                    raise ValueError(f"GIF loop count must be 0 (infinite), got {metadata['loop_count']!r}")
                expected_delays = expected_frame_delays(fps, len(frames))
                actual_delays = metadata["frame_delays_centiseconds"]
                if actual_delays != expected_delays:
                    mismatch = next(
                        index
                        for index, (actual, expected) in enumerate(zip(actual_delays, expected_delays))
                        if actual != expected
                    )
                    raise ValueError(
                        f"GIF per-frame centisecond delay differs at frame {mismatch}: "
                        f"expected {expected_delays[mismatch]}, got {actual_delays[mismatch]}"
                    )
                expected_duration = manifest["duration_seconds"]
                duration_tolerance = 0.02
                if abs(metadata["duration_seconds"] - expected_duration) > duration_tolerance:
                    raise ValueError(
                        f"GIF duration {metadata['duration_seconds']}s differs from fixture duration "
                        f"{expected_duration:.4f}s by more than {duration_tolerance:.4f}s"
                    )
                metadata["expected_duration_seconds"] = expected_duration
                metadata["expected_frame_delays_centiseconds"] = expected_delays
                metadata["duration_tolerance_seconds"] = duration_tolerance
                result["gif"] = metadata
                output_hash = digest(temporary_gif)
                result["output_sha256"] = output_hash
                result["output_bytes"] = metadata["bytes"]
                hashes = retained_hashes if retained_hashes is not None else set()
                if output_hash in hashes:
                    # this temporary GIF was created by this invocation; prior artifacts are untouched.
                    temporary_gif.unlink()
                    result["retained_output"] = False
                    result["retained_output_path"] = None
                    result["output"] = None
                else:
                    destination = output / "gifs" / name / f"{label}.gif"
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    if destination.exists():
                        raise FileExistsError(f"refusing to overwrite existing benchmark output: {destination}")
                    shutil.move(str(temporary_gif), destination)
                    hashes.add(output_hash)
                    result["retained_output"] = True
                    result["retained_output_path"] = str(destination)
                    result["output"] = str(destination)
                result["status"] = "ok"
            except ValueError as error:
                result["status"] = "invalid_output"
                result["error"] = str(error)
        else:
            result["status"] = "timeout" if result["timed_out"] else "failed"
        return result
    finally:
        shutil.rmtree(work)
        if "result" in locals():
            result["elapsed_seconds"] = time.perf_counter() - total_started


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="new result directory")
    parser.add_argument("--fixture", type=Path, help="existing synthetic fixture directory; generated if omitted")
    parser.add_argument("--frames", type=int, default=240, help="frames to generate when fixture is omitted")
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=360)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument(
        "--profile",
        choices=("mixed", "mostly-static-ui", "fast-scrolling", "high-motion-gradient-cursor"),
        default="mixed",
        help="synthetic scene profile for a generated fixture",
    )
    parser.add_argument("--runs", type=int, default=7, help="warm runs per candidate after one cold run")
    parser.add_argument("--imageio-app-binary", type=Path, help="reuse a previously compiled app candidate helper")
    parser.add_argument("--timeout", type=float, default=180, help="total seconds allowed per benchmark path")
    parser.add_argument(
        "--candidates",
        nargs="+",
        choices=CANDIDATES,
        default=PRIMARY_MATRIX_CANDIDATES,
        help="paths to run (default: the documented five-path primary matrix; imageio-app is an optional additional comparison)",
    )
    parser.add_argument("--magick-diffusion-amount", type=diffusion_amount, default=100, metavar="0..100", help="ImageMagick Floyd-Steinberg diffusion amount as a percentage (default: 100)")
    args = parser.parse_args()
    if args.runs < 1 or args.timeout <= 0:
        parser.error("runs and timeout must be positive")
    args.output.mkdir(parents=True, exist_ok=False)
    fixture = args.fixture.resolve() if args.fixture else args.output / "fixture"
    if args.fixture is None:
        generate = [
            sys.executable,
            str(ROOT / "generate_fixture.py"),
            "--output",
            str(fixture),
            "--frames",
            str(args.frames),
            "--width",
            str(args.width),
            "--height",
            str(args.height),
            "--seed",
            str(args.seed),
            "--profile",
            args.profile,
        ]
        subprocess.run(generate, check=True)
    manifest_path = fixture / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    frames = sorted(fixture.glob("frame_*.png"))
    if len(frames) != manifest["frame_count"]:
        raise ValueError("fixture frame count differs from manifest")
    fps = manifest["fps"]
    tools = discover(args.output, args.imageio_app_binary)
    availability = {name: path_availability(name, tools) for name in CANDIDATES}
    time_probe = capture(["/usr/bin/time", "-l", "/usr/bin/true"])
    use_system_time = time_probe.get("exit_code") == 0
    posix_time_probe = capture(["/usr/bin/time", "-p", "/usr/bin/true"])
    use_posix_time = not use_system_time and posix_time_probe.get("exit_code") == 0
    measurement_mode = "system_time" if use_system_time else "posix_time_and_sampled_ps" if use_posix_time else "sampled_ps"
    selected = list(dict.fromkeys(args.candidates))
    records = []
    retained_hashes = {name: set() for name in selected}
    (args.output / "raw.json").write_text("[]\n")
    for round_index in range(args.runs + 1):
        order = candidate_order(selected, round_index)
        for name in order:
            if not availability[name]["available"]:
                continue
            label = "cold" if round_index == 0 else f"warm-{round_index:02d}"
            print(f"running {name} {label}", flush=True)
            try:
                result = run_one(name, tools, manifest, frames, args.output, label, args.timeout, use_system_time, args.magick_diffusion_amount, retained_hashes[name], use_posix_time)
            except (OSError, ValueError) as error:
                failed_work = args.output / "work" / f"{name}-{label}"
                failed_commands = command_sequence_for(name, tools, fps, frames, failed_work / "output.gif", failed_work, args.magick_diffusion_amount)
                result = {"status": "runner_error", "error": str(error), "command": failed_commands[0]["command"], "commands": [stage["command"] for stage in failed_commands], "elapsed_seconds": None, "cpu_user_seconds": None, "cpu_system_seconds": None, "exit_code": None, "timed_out": False, "peak_workspace_bytes_sampled": None, "peak_resident_bytes_reported": None, "memory_measurement": "unavailable", "stdout": "", "stderr": ""}
            result.update({"candidate": name, "run": label, "round": round_index})
            result["magick_diffusion_amount_percent"] = args.magick_diffusion_amount if name in ("magick", "magick-unoptimized") else None
            records.append(result)
            (args.output / "raw.json").write_text(json.dumps(records, indent=2) + "\n")
    summary = {}
    for name in selected:
        samples = [sample for sample in records if sample["candidate"] == name]
        warm = [sample["elapsed_seconds"] for sample in samples if sample["run"].startswith("warm-") and sample["status"] == "ok"]
        path = availability[name]
        summary[name] = {
            "available": path["available"],
            "required_tools": path["required_tools"],
            "missing_tools": path["missing_tools"],
            "reason": path["reason"],
            "magick_diffusion_amount_percent": args.magick_diffusion_amount if name in ("magick", "magick-unoptimized") else None,
            "status": "unavailable" if not path["available"] else "ok" if len(warm) == args.runs else "incomplete",
            "successful_warm_runs": len(warm),
            "median_warm_seconds": statistics.median(warm) if warm else None,
            "p90_warm_seconds": percentile(warm, 0.9) if warm else None,
            "samples": [summary_sample(sample) for sample in samples],
        }
    report = {"environment": environment(), "fixture": {"path": str(fixture), "manifest": manifest, "manifest_sha256": digest(manifest_path), "frames_sha256": fixture_digest(frames)}, "tools": tools, "path_availability": availability, "system_time_probe": time_probe, "posix_time_probe": posix_time_probe, "measurement_mode": measurement_mode, "runs_requested": args.runs, "cold_run_definition": "the first invocation of each path in this series; operating-system caches are not flushed", "magick_diffusion_amount_percent": args.magick_diffusion_amount, "timeout_seconds": args.timeout, "summary": summary, "limits": ["this measures offline PNG-to-GIF encoding, not capture or stop-to-preview latency", "per-frame centisecond delays and infinite-loop metadata must match the fixture/output contract", "peak workspace bytes are polled every 20 ms and can miss short-lived files", "macOS /usr/bin/time -l reports command CPU/RSS when available; otherwise /usr/bin/time -p reports user/system CPU and sampled ps sums RSS for the timer process and descendants, which can miss short peaks", "GIF parsing checks structure and metadata, not visual fidelity or playback in another app"]}
    (args.output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    print(f"raw results: {args.output / 'raw.json'}")
    print(f"environment and summary: {args.output / 'summary.json'}")


if __name__ == "__main__":
    main()
