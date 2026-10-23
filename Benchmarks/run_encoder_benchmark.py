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
CANDIDATES = ("gifski", "magick", "imageio")
RSS_PATTERN = re.compile(r"(\d+)\s+maximum resident set size")
CPU_PATTERN = re.compile(r"([\d.]+)\s+real\s+([\d.]+)\s+user\s+([\d.]+)\s+sys")


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


def environment():
    return {
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "platform": platform.platform(),
        "machine": platform.machine(),
        "mac_model": capture(["sysctl", "-n", "hw.model"]),
        "memory_bytes": capture(["sysctl", "-n", "hw.memsize"]),
        "os_version": capture(["sw_vers"]),
        "power_settings": capture(["pmset", "-g", "custom"]),
        "xcode": capture(["xcodebuild", "-version"]),
        "git_commit": capture(["git", "rev-parse", "HEAD"]),
        "thermal_state": "not sampled; record manually before interpreting results",
    }


def discover(output):
    found = {}
    for name in ("gifski", "magick"):
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
    return found


def command_for(name, tools, fps, frames, output):
    binary = tools[name]["path"]
    if name == "gifski":
        return [binary, "--fps", str(fps), "--quality", "90", "--repeat", "0", "--no-sort", "-o", str(output), *map(str, frames)]
    if name == "magick":
        return [binary, "-delay", f"1x{fps}", *map(str, frames), "-loop", "0", "-dither", "FloydSteinberg", "-define", "dither:diffusion-amount=100%", "-colors", "256", "-layers", "Optimize", str(output)]
    return [binary, str(fps), str(output), *map(str, frames)]


def run_command(command, work, timeout_seconds, use_system_time):
    peak_bytes = 0
    peak_rss_bytes = None
    done = threading.Event()
    wrapped = ["/usr/bin/time", "-l", *command] if use_system_time else command
    started = time.perf_counter()
    process = subprocess.Popen(wrapped, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)

    def monitor():
        nonlocal peak_bytes, peak_rss_bytes
        while not done.wait(0.02):
            peak_bytes = max(peak_bytes, tree_bytes(work))
            if not use_system_time:
                sample = capture(["ps", "-o", "rss=", "-p", str(process.pid)])
                if sample.get("exit_code") == 0 and sample["stdout"].strip().isdigit():
                    peak_rss_bytes = max(peak_rss_bytes or 0, int(sample["stdout"].strip()) * 1024)

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
    cpu = CPU_PATTERN.search(stderr) if use_system_time else None
    return {"command": command, "elapsed_seconds": elapsed, "cpu_user_seconds": float(cpu.group(2)) if cpu else None, "cpu_system_seconds": float(cpu.group(3)) if cpu else None, "exit_code": process.returncode, "timed_out": timed_out, "peak_workspace_bytes_sampled": peak_bytes, "peak_resident_bytes_reported": int(match.group(1)) if match else peak_rss_bytes, "memory_measurement": "system_time" if match else "sampled_ps" if peak_rss_bytes is not None else "unavailable", "stdout": stdout[-16000:], "stderr": stderr[-16000:]}


def run_one(name, tools, fps, frames, output, label, timeout_seconds, use_system_time):
    work = output / "work" / f"{name}-{label}"
    work.mkdir(parents=True)
    temporary_gif = work / "output.gif"
    command = command_for(name, tools, fps, frames, temporary_gif)
    try:
        result = run_command(command, work, timeout_seconds, use_system_time)
        if result["exit_code"] == 0 and not result["timed_out"] and temporary_gif.exists():
            try:
                metadata = gif_metadata(temporary_gif)
                if metadata["frame_count"] == 0:
                    raise ValueError("GIF has no frames")
                if metadata["frame_count"] != len(frames):
                    raise ValueError(f"GIF frame count {metadata['frame_count']} differs from fixture count {len(frames)}")
                expected_duration = len(frames) / fps
                duration_tolerance = 0.02
                if abs(metadata["duration_seconds"] - expected_duration) > duration_tolerance:
                    raise ValueError(
                        f"GIF duration {metadata['duration_seconds']}s differs from fixture duration "
                        f"{expected_duration:.4f}s by more than {duration_tolerance:.4f}s"
                    )
                metadata["expected_duration_seconds"] = expected_duration
                metadata["duration_tolerance_seconds"] = duration_tolerance
                result["gif"] = metadata
                destination = output / "gifs" / name / f"{label}.gif"
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(temporary_gif), destination)
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="new result directory")
    parser.add_argument("--fixture", type=Path, help="existing synthetic fixture directory; generated if omitted")
    parser.add_argument("--frames", type=int, default=240, help="frames to generate when fixture is omitted")
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=360)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--runs", type=int, default=7, help="warm runs per candidate after one cold run")
    parser.add_argument("--timeout", type=float, default=180, help="seconds allowed per encoding")
    parser.add_argument("--candidates", nargs="+", choices=CANDIDATES, default=CANDIDATES)
    args = parser.parse_args()
    if args.runs < 1 or args.timeout <= 0:
        parser.error("runs and timeout must be positive")
    args.output.mkdir(parents=True, exist_ok=False)
    fixture = args.fixture.resolve() if args.fixture else args.output / "fixture"
    if args.fixture is None:
        generate = [sys.executable, str(ROOT / "generate_fixture.py"), "--output", str(fixture), "--frames", str(args.frames), "--width", str(args.width), "--height", str(args.height), "--seed", str(args.seed)]
        subprocess.run(generate, check=True)
    manifest_path = fixture / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    frames = sorted(fixture.glob("frame_*.png"))
    if len(frames) != manifest["frame_count"]:
        raise ValueError("fixture frame count differs from manifest")
    fps = manifest["fps"]
    available = discover(args.output)
    time_probe = capture(["/usr/bin/time", "-l", "/usr/bin/true"])
    use_system_time = time_probe.get("exit_code") == 0
    selected = list(dict.fromkeys(args.candidates))
    records = []
    (args.output / "raw.json").write_text("[]\n")
    for round_index in range(args.runs + 1):
        order = selected if round_index % 2 == 0 else list(reversed(selected))
        for name in order:
            if not available[name]["available"]:
                continue
            label = "cold" if round_index == 0 else f"warm-{round_index:02d}"
            print(f"running {name} {label}", flush=True)
            try:
                result = run_one(name, available, fps, frames, args.output, label, args.timeout, use_system_time)
            except (OSError, ValueError) as error:
                result = {"status": "runner_error", "error": str(error), "command": command_for(name, available, fps, frames, args.output / "work" / f"{name}-{label}" / "output.gif"), "elapsed_seconds": None, "cpu_user_seconds": None, "cpu_system_seconds": None, "exit_code": None, "timed_out": False, "peak_workspace_bytes_sampled": None, "peak_resident_bytes_reported": None, "memory_measurement": "unavailable", "stdout": "", "stderr": ""}
            result.update({"candidate": name, "run": label, "round": round_index})
            records.append(result)
            (args.output / "raw.json").write_text(json.dumps(records, indent=2) + "\n")
    summary = {}
    for name in selected:
        samples = [sample for sample in records if sample["candidate"] == name]
        warm = [sample["elapsed_seconds"] for sample in samples if sample["run"] != "cold" and sample["status"] == "ok"]
        summary[name] = {"available": available[name]["available"], "status": "unavailable" if not available[name]["available"] else "ok" if len(warm) == args.runs else "incomplete", "successful_warm_runs": len(warm), "median_warm_seconds": statistics.median(warm) if warm else None, "p90_warm_seconds": percentile(warm, 0.9) if warm else None, "samples": [{"run": sample["run"], "status": sample["status"], "elapsed_seconds": sample["elapsed_seconds"], "cpu_user_seconds": sample["cpu_user_seconds"], "cpu_system_seconds": sample["cpu_system_seconds"], "bytes": sample.get("gif", {}).get("bytes"), "frame_count": sample.get("gif", {}).get("frame_count"), "duration_seconds": sample.get("gif", {}).get("duration_seconds"), "peak_resident_bytes_reported": sample["peak_resident_bytes_reported"], "peak_workspace_bytes_sampled": sample["peak_workspace_bytes_sampled"]} for sample in samples]}
    report = {"environment": environment(), "fixture": {"path": str(fixture), "manifest": manifest, "manifest_sha256": digest(manifest_path), "frames_sha256": fixture_digest(frames)}, "tools": available, "system_time_probe": time_probe, "runs_requested": args.runs, "timeout_seconds": args.timeout, "summary": summary, "limits": ["this measures offline PNG-to-GIF encoding, not capture or stop-to-preview latency", "peak workspace bytes are polled every 20 ms and can miss short-lived files", "memory uses macOS /usr/bin/time -l when available, otherwise sampled ps; either may include helper processes or miss short peaks", "GIF parsing checks structure and metadata, not visual fidelity or playback in another app"]}
    (args.output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    print(f"raw results: {args.output / 'raw.json'}")
    print(f"environment and summary: {args.output / 'summary.json'}")


if __name__ == "__main__":
    main()
