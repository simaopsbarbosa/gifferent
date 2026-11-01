#!/usr/bin/env python3
"""compare the old and new manual quality defaults on published fixtures."""

import argparse
import hashlib
import json
import math
import platform
import re
import statistics
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

from run_encoder_benchmark import capture, digest, fixture_digest, gif_metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--static-fixture", type=Path, required=True)
    parser.add_argument("--motion-fixture", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--runs", type=int, default=7)
    args = parser.parse_args()
    if args.runs < 3:
        parser.error("at least three warm runs are required")
    root = Path(__file__).resolve().parent
    reference = json.loads((root / "reviews/gifski-quality-sweep-2026-10-24/summary.json").read_text())
    binary = root.parent / "Vendor/Gifski-1.34.0/gifski"
    args.output.mkdir(parents=True, exist_ok=False)
    report = {
        "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
        "environment": {
            "macos": platform.mac_ver()[0],
            "machine": capture(["sysctl", "-n", "hw.model"]),
            "power": capture(["pmset", "-g", "batt"]),
            "toolchain": capture(["xcodebuild", "-version"]),
        },
        "binary_sha256": digest(binary),
        "binary_version": capture([str(binary), "--version"]),
        "warm_runs": args.runs,
        "settings": {"fps": 24, "repeat": 0, "no_sort": True, "qualities": [90, 100]},
        "profiles": {},
    }
    report["environment"]["power"]["stdout"] = re.sub(
        r"\(id=\d+\)\t?", "", report["environment"]["power"]["stdout"])
    for name, fixture in [
        ("mostly-static-ui", args.static_fixture),
        ("high-motion-gradient-cursor", args.motion_fixture),
    ]:
        frames = sorted(fixture.glob("frame_*.png"))
        manifest_hash = digest(fixture / "manifest.json")
        frame_hash = fixture_digest(frames)
        expected = reference["profiles"][name]
        if manifest_hash != expected["fixture_manifest_sha256"] or frame_hash != expected["frame_set_sha256"]:
            raise ValueError(f"{name}: fixture differs from recorded baseline")
        profile = {"manifest_sha256": manifest_hash, "frames_sha256": frame_hash, "qualities": {}}
        for quality in [90, 100]:
            samples = []
            for index in range(args.runs + 1):
                output = args.output / f"{name}-quality-{quality}-{index}.gif"
                command = [str(binary), "--fps", "24", "--quality", str(quality), "--repeat", "0", "--no-sort", "-o", str(output), *map(str, frames)]
                started = time.perf_counter()
                result = subprocess.run(["/usr/bin/time", "-l", *command], capture_output=True, text=True, timeout=180, check=True)
                elapsed = time.perf_counter() - started
                metadata = gif_metadata(output)
                if (metadata["width"], metadata["height"], metadata["frame_count"], metadata["duration_seconds"], metadata["loop_count"]) != (640, 360, 240, 10.0, 0):
                    raise ValueError(f"invalid output metadata: {metadata}")
                delays = metadata.pop("frame_delays_centiseconds")
                metadata["frame_delays_sha256"] = hashlib.sha256(
                    json.dumps(delays, separators=(",", ":")).encode()).hexdigest()
                rss = re.search(r"(\d+)\s+maximum resident set size", result.stderr)
                if rss is None:
                    raise ValueError("peak resident memory was not recorded")
                approved = root / f"reviews/gifski-quality-sweep-2026-10-24/gifs/{name}-quality-{quality}.gif"
                samples.append({
                    "cold": index == 0,
                    "seconds": elapsed,
                    "peak_rss_bytes": int(rss[1]),
                    "file_bytes": output.stat().st_size,
                    "sha256": digest(output),
                    "matches_reviewed_animation": digest(output) == digest(approved),
                    "metadata": metadata,
                })
                output.unlink()
            warm = samples[1:]
            summary = {}
            for key in ["seconds", "peak_rss_bytes", "file_bytes"]:
                values = sorted(sample[key] for sample in warm)
                summary[key] = {"median": statistics.median(values), "p90": values[math.ceil(len(values) * 0.9) - 1]}
            profile["qualities"][str(quality)] = {"samples": samples, "summary": summary}
        report["profiles"][name] = profile
    (args.output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({name: {q: v["summary"] for q, v in p["qualities"].items()} for name, p in report["profiles"].items()}, indent=2))


if __name__ == "__main__":
    main()
