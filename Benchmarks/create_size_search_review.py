#!/usr/bin/env python3
"""build an exact-cadence Gifski size-search review from published fixtures."""

import argparse
import hashlib
import json
import math
import shutil
import subprocess
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

from run_encoder_benchmark import expected_frame_delays, fixture_digest, gif_metadata


PROFILES = (
    "mostly-static-ui",
    "mixed",
    "fast-scrolling",
    "high-motion-gradient-cursor",
)
SCALES = (100, 75, 50, 25)
RATES = (24, 18, 12, 8)
EXPECTED_MANIFESTS = {
    "mostly-static-ui": "6e2f785f8c29a9ca43cd1bbf91dd636e0405822c01438cb8a27ef1a7a35a28fa",
    "mixed": "cd2a9ffb73a5908e221ae2fd0e28233b7a1ce426dee9f9b4239371c35b9c07e2",
    "fast-scrolling": "d31d28bcba4880b86dac358e81a87e466fe74631414db7e69528405338dc8eec",
    "high-motion-gradient-cursor": "8a90e5f8d09fe44045642bc1fb744d3865494ad8ede21e36b95ab06759f71c64",
}
EXPECTED_FRAME_SETS = {
    "mostly-static-ui": "d42ed02d552de0db283b9a2d720ac782b7b62dc8dd7c41817da0837b3ce71fc2",
    "mixed": "a2e07a4980e7b437bc1e44d6a9d8ff7f11c70126abaeeb9ad3a580ecd1143c9d",
    "fast-scrolling": "e0750bce46287c335993b3e2610505b0debe4f18fe7cfa25e700ff1cac850885",
    "high-motion-gradient-cursor": "8436939cbc8b536dcc3ea3423669f4f0ccdda1dc14a75a3e5eee4b652b4c0c01",
}


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sampled_indices(source_fps, target_fps, frame_count):
    """select nearest source timestamp with exact integer half-up rounding."""
    return [math.floor(index * source_fps / target_fps + 0.5) for index in range(frame_count)]


def run(command):
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(map(str, command))}\n"
            f"{result.stdout}\n{result.stderr}"
        )
    return result


def profile_fixture(name, path):
    path = Path(path)
    manifest_path = path / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    frames = sorted(path.glob("frame_*.png"))
    if (
        manifest.get("profile") != name
        or manifest.get("width") != 640
        or manifest.get("height") != 360
        or manifest.get("frame_count") != 240
        or manifest.get("fps") != 24
        or len(frames) != 240
    ):
        raise ValueError(f"unexpected fixture contract for {name}: {manifest}")
    manifest_hash = sha256(manifest_path)
    frame_hash = fixture_digest(frames)
    if manifest_hash != EXPECTED_MANIFESTS[name] or frame_hash != EXPECTED_FRAME_SETS[name]:
        raise ValueError(f"published fixture hashes do not match for {name}")
    return path, frames, manifest_hash, frame_hash


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixtures-json", type=Path, required=True)
    parser.add_argument("--baselines-json", type=Path, required=True)
    parser.add_argument("--gifski", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--magick", type=Path, default=Path("/opt/homebrew/bin/magick"))
    args = parser.parse_args()

    fixture_paths = json.loads(args.fixtures_json.read_text())
    baseline_paths = json.loads(args.baselines_json.read_text())
    if set(fixture_paths) != set(PROFILES) or set(baseline_paths) != set(PROFILES):
        raise ValueError("fixture and baseline maps must include all four published profiles")
    if args.output.exists():
        raise ValueError(f"output already exists: {args.output}")
    args.output.mkdir(parents=True)
    gifs = args.output / "gifs"
    gifs.mkdir()

    version = run([str(args.gifski), "--version"]).stdout.strip()
    binary_hash = sha256(args.gifski)
    magick_version = run([str(args.magick), "--version"]).stdout.splitlines()[0]
    result_profiles = {}

    for profile in PROFILES:
        _, frames, manifest_hash, frame_hash = profile_fixture(profile, fixture_paths[profile])
        baseline_path = Path(baseline_paths[profile])
        baseline_meta = gif_metadata(baseline_path)
        expected_baseline = {
            "width": 640,
            "height": 360,
            "frame_count": 240,
            "duration_seconds": 10.0,
            "frame_delays_centiseconds": expected_frame_delays(24, 240),
            "loop_count": 0,
        }
        if any(baseline_meta.get(key) != value for key, value in expected_baseline.items()):
            raise ValueError(f"q90 baseline timing/metadata invalid for {profile}: {baseline_meta}")

        profile_results = []
        with tempfile.TemporaryDirectory(prefix="gifferent-size-search-") as temporary:
            work = Path(temporary)
            prepared_by_scale = {100: frames}
            preparation_seconds_by_scale = {100: 0.0}
            for scale in SCALES:
                if scale == 100:
                    continue
                width = 640 * scale // 100
                height = 360 * scale // 100
                scale_dir = work / f"{scale:03d}pct"
                scale_dir.mkdir()
                preparation_start = time.perf_counter()
                scaled_frames = []
                for source_index, source_path in enumerate(frames):
                    prepared_path = scale_dir / f"frame_{source_index:04d}.png"
                    run([
                        str(args.magick),
                        str(source_path),
                        "-filter",
                        "Lanczos",
                        "-resize",
                        f"{width}x{height}!",
                        str(prepared_path),
                    ])
                    scaled_frames.append(prepared_path)
                prepared_by_scale[scale] = scaled_frames
                preparation_seconds_by_scale[scale] = time.perf_counter() - preparation_start

            for scale in SCALES:
                width = 640 * scale // 100
                height = 360 * scale // 100
                for fps in RATES:
                    filename = f"{profile}__{scale:03d}pct__{fps:02d}fps.gif"
                    output_path = gifs / filename
                    if scale == 100 and fps == 24:
                        shutil.copyfile(baseline_path, output_path)
                        metadata = gif_metadata(output_path)
                        source = "reused-q90-baseline"
                        encode_seconds = None
                    else:
                        indices = sampled_indices(24, fps, fps * 10)
                        if (
                            len(indices) != fps * 10
                            or len(set(indices)) != len(indices)
                            or indices[0] != 0
                            or indices[-1] >= 240
                            or any(a >= b for a, b in zip(indices, indices[1:]))
                        ):
                            raise ValueError(f"source fixture cannot support an exact {fps} fps sample")
                        prepared = [prepared_by_scale[scale][index] for index in indices]
                        command = [
                            str(args.gifski),
                            "--fps",
                            str(fps),
                            "--quality",
                            "90",
                            "--repeat",
                            "0",
                            "--no-sort",
                            "-o",
                            str(output_path),
                            *map(str, prepared),
                        ]
                        encode_start = time.perf_counter()
                        run(command)
                        encode_seconds = time.perf_counter() - encode_start
                        metadata = gif_metadata(output_path)
                        source = "generated"

                    expected = {
                        "width": width,
                        "height": height,
                        "frame_count": fps * 10,
                        "duration_seconds": 10.0,
                        "frame_delays_centiseconds": expected_frame_delays(fps, fps * 10),
                        "loop_count": 0,
                    }
                    failures = [key for key, value in expected.items() if metadata.get(key) != value]
                    entry = {
                        "file": filename,
                        "profile": profile,
                        "scale_percent": scale,
                        "fps": fps,
                        "source": source,
                        "width": width,
                        "height": height,
                        "frame_count": metadata.get("frame_count"),
                        "duration_seconds": metadata.get("duration_seconds"),
                        "loop_count": metadata.get("loop_count"),
                        "timing_valid": not failures,
                        "timing_failures": failures,
                        "bytes": output_path.stat().st_size,
                        "sha256": sha256(output_path),
                        "encode_seconds": encode_seconds,
                        "preparation_seconds": preparation_seconds_by_scale[scale],
                        "source_manifest_sha256": manifest_hash,
                        "source_frame_set_sha256": frame_hash,
                        "sample_index_first": 0,
                        "sample_index_last": 239 if source == "reused-q90-baseline" else sampled_indices(24, fps, fps * 10)[-1],
                        "sample_rule": "nearest source timestamp; ties round forward" if source == "generated" else "existing full-scale 24 fps q90 sample",
                    }
                    if source == "reused-q90-baseline":
                        entry["encode_seconds"] = "see published full-matrix cold/warm timing"
                    if failures:
                        raise ValueError(f"invalid output metadata {profile}/{scale}/{fps}: {failures}")
                    profile_results.append(entry)
                    print(f"{profile} {scale}% {fps} fps: {entry['bytes']} bytes, {entry['encode_seconds']} s", flush=True)
        result_profiles[profile] = profile_results

    summary = {
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "gifski_version": version,
        "gifski_sha256": binary_hash,
        "gifski_path": str(args.gifski),
        "scaling_tool_version": magick_version,
        "scaling_tool_path": str(args.magick),
        "quality": 90,
        "fps_targets": list(RATES),
        "scale_targets_percent": list(SCALES),
        "source_contract": {"width": 640, "height": 360, "frames": 240, "fps": 24, "duration_seconds": 10},
        "timing_contract": "cumulative rounded-centisecond frame delays, 10.0 seconds, infinite loop",
        "profiles": result_profiles,
    }
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    main()
