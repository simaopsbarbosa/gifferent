# benchmark evidence

use the same synthetic source fixtures and machine configuration when comparing a change against its baseline. keep generated frames and outputs under `Benchmarks/generated/` or `Benchmarks/outputs/`; both are ignored by Git. commit the fixture generator, exact commands, small reviewable results, and representative visual comparisons once they exist.

## synthetic source fixture

generate the default 10-second, 24 fps fixture with Python's standard library:

```sh
python3 Benchmarks/generate_fixture.py --output Benchmarks/generated/reference-640x360 --width 640 --height 360 --seed 7 --frames 240
```

the output directory must be new. the generator writes `frame_0000.png` through `frame_0239.png` and a `manifest.json`. frame `n` starts at `n / 24` seconds; each frame lasts `1 / 24` second. the manifest records the seed, dimensions, frame count, rate, and timing rule. the pixels are synthetic: bitmap text, flat UI shapes, a moving cursor-like mark, and moving color gradients. its colors and layout are benchmark inputs, not approved product artwork. no screen content is read.

for a quick smoke run, use `--frames 6 --width 320 --height 180` with a different new output directory. keep the same seed, dimensions, and frame count for every candidate in one comparison.

for each run, record:

- commit, date, macOS and Xcode versions, Mac model, chip, memory, power mode, and thermal conditions;
- fixture name, dimensions, duration, frame rate, cursor content, motion and text characteristics;
- tool name, version, checksum, license, flags, and whether encoding happens during capture or after stop;
- sample count, warmup policy, timing statistic, start-to-ready and stop-to-preview latency, total processing time, peak memory, temporary disk use, CPU use, dropped frames, and output bytes;
- validity and visual review of animation, text, motion, dithering, and color; include reviewer and known limits;
- baseline and candidate results on the same input and machine, with a conclusion tied to measured evidence.

the speed goals in [vision.md](../vision.md) remain targets until runs on an agreed reference Mac and fixture set establish them. the acceptable visual quality floor is an open product decision in [decisions.md](../decisions.md).

## exploratory encoder run

on the [reference Mac](environment.md), run one command from the repository root. the output directory must not exist yet:

```sh
python3 Benchmarks/run_encoder_benchmark.py --output Benchmarks/outputs/reference-640x360-01 --frames 240 --width 640 --height 360 --runs 7
```

the runner creates the synthetic fixture once, records one cold and seven warm samples for each available candidate, and alternates candidate order. it tries `gifski` and `magick` from `PATH`, then compiles the benchmark-only ImageIO helper with `xcrun swiftc`. missing or unbuildable candidates are reported as unavailable. `gifski` uses its documented quality default of 90 explicitly and `--no-sort` to preserve manifest order; ImageMagick's `-loop 0` follows the input frames so it applies to the output animation. each successful GIF is retained under `gifs/` for visual review. `raw.json` contains exact argument arrays, elapsed time, CPU user/system time when obtainable, exit status, sampled peak workspace bytes, peak resident bytes when obtainable, stderr, and parsed GIF metadata for every run. `summary.json` contains environment/tool provenance, manifest and frame-content checksums, median/p90 of successful warm runs, and the per-run size, frame count, and duration. a failed, invalid, timed-out, incomplete-frame, or out-of-tolerance-duration run removes its partial GIF and work directory, remains in both reports, and is not counted in the statistic.

run the harness checks with `python3 -m unittest discover -s Benchmarks -p 'test_encoder_benchmark.py' -v`. for a quick real-encoder smoke test, use a new output directory with `--frames 6 --width 320 --height 180 --runs 1`; it does not provide a valid performance comparison.

the runner measures offline PNG-to-GIF conversion. it does not measure screen capture, streaming encode, stop-to-preview latency, or visual quality. the ImageIO helper is a native comparison path, not the approved bundled CLI. GIF timing is quantized to centiseconds; candidates must match fixture frame count and cumulative duration within 20 ms total to enter timing statistics. compare parsed per-frame delays and visual playback with the fixture manifest during review. workspace size is sampled every 20 ms and can miss short-lived files. memory uses macOS `/usr/bin/time -l` when allowed, then sampled `ps` as a fallback; a short run or restricted host can yield `null`. the tool binary and build still need an exact license, dependency, architecture, signature, and source audit before packaging. no result from this harness alone selects a release encoder.
