#!/usr/bin/env python3
"""measure the production Swift compression adapter and bounded search on synthetic GIFs."""

import argparse
import json
import math
import shutil
import statistics
import subprocess
import time
from pathlib import Path

from run_encoder_benchmark import capture, digest, fixture_digest, gif_metadata, process_tree_rss_bytes, tree_bytes

ROOT = Path(__file__).resolve().parent.parent
SOURCES = [
    "Sources/Recording/SessionWorkspaceStore.swift",
    "Sources/Encoding/GIFEditModel.swift",
    "Sources/Encoding/OriginalGIFEncoder.swift",
    "Sources/Encoding/GIFCompression.swift",
    "Sources/Encoding/GifskiCLICompressor.swift",
    "Benchmarks/app_size_search.swift",
]


def run(command):
    return subprocess.run(command, check=True, capture_output=True, text=True).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gifski", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--runs", type=int, default=7)
    parser.add_argument("--baseline-harness", type=Path)
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--measure-prepared", action="store_true")
    args = parser.parse_args()
    output = args.output.resolve()
    if args.runs < 7:
        parser.error("at least seven warm samples are required")
    if not args.measure_prepared:
        output.mkdir(parents=True, exist_ok=False)
    harness = output / "app-size-search"
    if not args.measure_prepared:
        run(["xcrun", "swiftc", "-module-cache-path", str(output / "module-cache"), "-O",
             "-parse-as-library", *[str(ROOT / source) for source in SOURCES], "-o", str(harness)])
        fixture_rows = []
        for profile in ("mostly-static-ui", "high-motion-gradient-cursor"):
            for seconds in (10, 30):
                # Keep the 30-second small-region workload under the adapter's PNG workspace cap.
                width, height = (640, 360) if seconds == 10 else (320, 180)
                name = f"{profile}-{seconds}s-{width}x{height}"
                fixture = output / f"fixture-{name}"
                run(["python3", str(ROOT / "Benchmarks/generate_fixture.py"), "--output", str(fixture),
                     "--width", str(width), "--height", str(height), "--seed", "7", "--frames",
                     str(seconds * 24), "--profile", profile])
                source_directory = output / f"source-{name}"
                run([str(harness), str(args.gifski), str(fixture), str(source_directory), "prepare"])
                source = source_directory / "source.gif"
                fixture_rows.append({"name": name, "fixture": str(fixture), "source": str(source),
                                     "fixture_sha256": fixture_digest(sorted(fixture.glob("frame_*.png"))),
                                     "source_sha256": digest(source), "source_metadata": gif_metadata(source)})
        (output / "fixtures.json").write_text(json.dumps(fixture_rows, indent=2) + "\n")
    if args.measure_prepared:
        run(["xcrun", "swiftc", "-module-cache-path", str(output / "module-cache"), "-O",
             "-parse-as-library", *[str(ROOT / source) for source in SOURCES], "-o", str(harness)])
    if args.prepare_only:
        print(f"prepared {output}")
        return
    fixtures = json.loads((output / "fixtures.json").read_text())
    environment = {"date_utc": capture(["date", "-u", "+%Y-%m-%dT%H:%M:%SZ"]),
                   "os": capture(["sw_vers"]), "xcode": capture(["xcodebuild", "-version"]),
                   "hardware": capture(["sysctl", "hw.model", "hw.memsize", "machdep.cpu.brand_string"]),
                   "power": capture(["pmset", "-g", "custom"]), "battery": capture(["pmset", "-g", "batt"]),
                   "thermal": capture(["pmset", "-g", "therm"]),
                   "git_commit": capture(["git", "-C", str(ROOT), "rev-parse", "HEAD"]),
                   "gifski_version": capture([str(args.gifski), "--version"]),
                   "gifski_sha256": digest(args.gifski), "harness_sha256": digest(harness),
                   "source_sha256": {source: digest(ROOT / source) for source in SOURCES}}
    if args.baseline_harness:
        environment["baseline_harness_sha256"] = digest(args.baseline_harness)
        environment["baseline_source_sha256"] = {
            source: digest(args.baseline_harness.parent / Path(source).name) for source in SOURCES[:-1]
        }
    (output / "environment.json").write_text(json.dumps(environment, indent=2) + "\n")
    # Fail instead of silently claiming unavailable process-tree memory measurements.
    run(["ps", "-axo", "pid=,ppid=,rss="])
    if args.baseline_harness:
        encode_samples = []
        for round_number in range(args.runs + 1):
            encoders = [("baseline", args.baseline_harness), ("current", harness)]
            if round_number % 2:
                encoders.reverse()
            for fixture in fixtures:
                for label, encoder in encoders:
                    directory = output / f"encode-{label}-{fixture['name']}-{round_number}"
                    command = [str(encoder), str(args.gifski), fixture["fixture"], str(directory), "prepare-edit"]
                    started = time.perf_counter()
                    command = ["/usr/bin/time", "-l", *command]
                    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                    peak_rss, peak_disk = 0, 0
                    while process.poll() is None:
                        snapshot = run(["ps", "-axo", "pid=,ppid=,rss="])
                        peak_rss = max(peak_rss, process_tree_rss_bytes(snapshot, process.pid) or 0)
                        peak_disk = max(peak_disk, tree_bytes(directory))
                        time.sleep(0.05)
                    stdout, stderr = process.communicate()
                    if process.returncode:
                        raise RuntimeError(f"edit encode failed: {stderr}")
                    gif = directory / "source.gif"
                    metadata = gif_metadata(gif)
                    expected_frames = fixture["source_metadata"]["frame_count"] - 2
                    expected_duration_cs = math.floor(expected_frames / 24 / 1.7 * 100 + 0.5)
                    if metadata["loop_count"] is not None or metadata["frame_count"] != expected_frames:
                        raise ValueError("edit output lost loop/trim intent")
                    if round(metadata["duration_seconds"] * 100) != expected_duration_cs:
                        raise ValueError("edit output duration mismatch")
                    encode_samples.append({"fixture": fixture["name"], "encoder": label, "round": round_number,
                                           "series": "cold" if round_number == 0 else "warm", "command": command,
                                           "wall_seconds": time.perf_counter() - started, "stderr": stderr,
                                           "peak_process_tree_rss_bytes": peak_rss,
                                           "peak_attempt_directory_bytes": peak_disk,
                                           "sha256": digest(gif), "metadata": metadata})
                    (output / "edit-encode-raw.json").write_text(json.dumps(encode_samples, indent=2) + "\n")
                    shutil.rmtree(directory)
                    print(f"edit {label} {fixture['name']} {round_number}: {encode_samples[-1]['wall_seconds']:.3f}s", flush=True)
        singleton = []
        for label, encoder in [("baseline", args.baseline_harness), ("current", harness)]:
            directory = output / f"singleton-{label}"
            run([str(encoder), str(args.gifski), fixtures[0]["fixture"], str(directory), "prepare-single"])
            singleton.append({"encoder": label, "metadata": gif_metadata(directory / "source.gif")})
        (output / "edit-singleton-correctness.json").write_text(json.dumps(singleton, indent=2) + "\n")
    workloads = fixtures + [
        {**fixture, "name": fixture["name"] + "-q100", "quality": 100}
        for fixture in fixtures if fixture["name"].startswith("high-motion")
    ]
    samples = []
    for round_number in range(args.runs + 1):
        ordered = workloads if round_number % 2 == 0 else list(reversed(workloads))
        for fixture in ordered:
            directory = output / f"run-{fixture['name']}-{round_number}"
            command = [str(harness), str(args.gifski), fixture["source"], str(directory), f"search{fixture.get('quality', 90)}"]
            started = time.perf_counter()
            command = ["/usr/bin/time", "-l", *command]
            process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            peak_rss, peak_disk, observations = 0, 0, 0
            while process.poll() is None:
                snapshot = run(["ps", "-axo", "pid=,ppid=,rss="])
                peak_rss = max(peak_rss, process_tree_rss_bytes(snapshot, process.pid) or 0)
                peak_disk = max(peak_disk, tree_bytes(directory))
                observations += 1
                time.sleep(0.05)
            stdout, stderr = process.communicate()
            row = {"fixture": fixture["name"], "round": round_number,
                   "series": "cold" if round_number == 0 else "warm", "command": command,
                   "wall_seconds": time.perf_counter() - started, "peak_process_tree_rss_bytes": peak_rss,
                   "peak_attempt_directory_bytes": peak_disk, "observations": observations,
                   "exit_code": process.returncode, "stderr": stderr}
            if process.returncode != 0:
                row["stdout"] = stdout
                samples.append(row)
                (output / "raw.json").write_text(json.dumps(samples, indent=2) + "\n")
                raise RuntimeError(f"search failed: {fixture['name']}: {stderr}")
            result = json.loads(stdout)
            row["result"] = result
            if len(result["retained_files"]) != 1 or len(result["attempts"]) != (12 if fixture.get("quality") == 100 else 4):
                raise ValueError("unexpected approved attempt count or retained output count")
            if result["selected_bytes"] != min(item["bytes"] for item in result["attempts"]):
                raise ValueError("search did not select the smallest result")
            row["output_sha256"] = digest(directory / result["retained_files"][0])
            samples.append(row)
            (output / "raw.json").write_text(json.dumps(samples, indent=2) + "\n")
            print(f"{fixture['name']} {round_number}: {result['seconds']:.3f}s {result['selected_bytes']} bytes", flush=True)
            if round_number > 0:
                shutil.rmtree(directory)
    summary = []
    for fixture in workloads:
        warm = [sample for sample in samples if sample["fixture"] == fixture["name"] and sample["series"] == "warm"]
        attempts = []
        for attempt_index in range(len(warm[0]["result"]["attempts"])):
            points = [sample["result"]["attempts"][attempt_index] for sample in warm]
            times = [point["seconds"] for point in points]
            attempts.append({**{key: value for key, value in points[0].items() if key != "seconds"},
                             "median_seconds": statistics.median(times),
                             "p90_seconds": sorted(times)[math.ceil(len(times) * 0.9) - 1]})
        times = [sample["result"]["seconds"] for sample in warm]
        summary.append({"fixture": fixture["name"], "warm_samples": len(warm),
                        "median_seconds": statistics.median(times),
                        "p90_seconds": sorted(times)[math.ceil(len(times) * 0.9) - 1],
                        "max_sampled_process_tree_rss_bytes": max(sample["peak_process_tree_rss_bytes"] for sample in warm),
                        "max_sampled_attempt_directory_bytes": max(sample["peak_attempt_directory_bytes"] for sample in warm),
                        "selected_scale": warm[0]["result"]["selected_scale"],
                        "selected_fps": warm[0]["result"]["selected_fps"],
                        "selected_bytes": warm[0]["result"]["selected_bytes"], "attempts": attempts})
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    if environment["source_sha256"] != {source: digest(ROOT / source) for source in SOURCES}:
        raise RuntimeError("production source changed during measurement; rerun the series")


if __name__ == "__main__":
    main()
