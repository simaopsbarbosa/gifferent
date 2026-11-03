#!/usr/bin/env python3
"""compare the previous 24 fps encoder path and approved 60/50 fps path on one timeline."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import platform
import re
import statistics
import subprocess
import time

import generate_fixture

ROOT = Path(__file__).resolve().parent.parent


def command(args):
    return subprocess.check_output(args, text=True).strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--runs", type=int, default=7)
    parser.add_argument("--fixture-root", type=Path, help="reuse a complete master 60 fps fixture set")
    args = parser.parse_args()
    if args.runs < 1:
        parser.error("runs must be positive")
    args.output.mkdir(parents=True, exist_ok=False)
    helper = args.output / "frame-rate-encode"
    sources = ["Sources/Recording/SessionWorkspaceStore.swift", "Sources/Encoding/GIFEditModel.swift",
               "Sources/Encoding/OriginalGIFEncoder.swift", "Benchmarks/frame_rate_encode.swift"]
    subprocess.run(["xcrun", "swiftc", "-O", "-module-cache-path", str(args.output / "module-cache"),
                    *[str(ROOT / item) for item in sources], "-o", str(helper)], check=True)
    report = {"machine": command(["sysctl", "-n", "hw.model"]), "os": platform.mac_ver()[0],
              "xcode": command(["xcodebuild", "-version"]), "power": command(["pmset", "-g", "custom"]),
              "battery": command(["pmset", "-g", "batt"]), "runs": args.runs,
              "source_sha256": {item: digest(ROOT / item) for item in sources}, "samples": [], "master_fps": 60, "seed": 7, "fixture_dimensions": [640, 360],
              "order": "alternating baseline/new by run", "p90_method": "nearest rank",
              "scope": "PNG sequence transform plus ImageIO encoding/metadata validation; excludes live capture and PNG creation"}
    for profile in ["mostly-static-ui", "high-motion-gradient-cursor"]:
        fixture = (args.fixture_root or args.output) / profile
        if args.fixture_root is None:
            fixture.mkdir()
        hashes = hashlib.sha256()
        for index in range(1800):
            path = fixture / f"frame_{index:04d}.png"
            if args.fixture_root is None:
                generate_fixture.write_png(path, generate_fixture.draw_frame(640, 360, index, 7, profile))
            hashes.update(path.read_bytes())
        report.setdefault("fixture_sha256", {})[profile] = hashes.hexdigest()
        for duration in [10, 30]:
            # alternate the two paths to reduce ordering bias; run zero is cold.
            for run in range(args.runs + 1):
                candidates = [(24, 24, "legacy"), (60, 50, "edit")]
                if run % 2:
                    candidates.reverse()
                for capture, output, mode in candidates:
                    name = f"{profile}-{duration}s-{capture}-{output}-{run}"
                    destination = args.output / f"{name}.gif"
                    invocation = [str(helper), str(fixture), str(capture), str(duration * capture),
                                  str(output), "1", mode, str(destination)]
                    start = time.perf_counter()
                    result = subprocess.run(["/usr/bin/time", "-l", *invocation], text=True, capture_output=True, check=True)
                    elapsed = time.perf_counter() - start
                    rss = int(re.search(r"(\d+)\s+maximum resident set size", result.stderr)[1])
                    sample = dict(json.loads(result.stdout), profile=profile, duration=duration, capture_fps=capture,
                                  output_fps=output, run=run, seconds=elapsed, peak_rss_bytes=rss,
                                  sha256=digest(destination))
                    report["samples"].append(sample)
                    if run != 1:
                        destination.unlink()
                    (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
                    print(name, round(elapsed, 3), rss, flush=True)
    summaries = []
    for profile in report["fixture_sha256"]:
        for duration in [10, 30]:
            for capture in [24, 60]:
                samples = [s for s in report["samples"] if s["profile"] == profile and s["duration"] == duration
                           and s["capture_fps"] == capture and s["run"] > 0]
                p90 = lambda key: sorted(s[key] for s in samples)[math.ceil(len(samples) * 0.9) - 1]
                summaries.append(dict(profile=profile, duration=duration, capture_fps=capture,
                    median_seconds=statistics.median(s["seconds"] for s in samples), p90_seconds=p90("seconds"),
                    median_rss_bytes=statistics.median(s["peak_rss_bytes"] for s in samples), p90_rss_bytes=p90("peak_rss_bytes"),
                    bytes=samples[0]["bytes"], captured_png_bytes=samples[0]["captured_png_bytes"]))
    report["summaries"] = summaries
    (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
