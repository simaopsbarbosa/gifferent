# benchmark evidence

use the same synthetic source fixtures and machine configuration when comparing a change against its baseline. keep generated frames and outputs under `Benchmarks/generated/` or `Benchmarks/outputs/`; both are ignored by Git. commit the fixture generator, exact commands, small reviewable results, and representative visual comparisons once they exist.

## synthetic source fixture

generate the default 10-second, 24 fps fixture with Python's standard library:

```sh
python3 Benchmarks/generate_fixture.py --output Benchmarks/generated/reference-640x360 --width 640 --height 360 --seed 7 --frames 240
```

the output directory must be new. the generator writes `frame_0000.png` through `frame_0239.png` and a `manifest.json`. frame `n` starts at `n / 24` seconds; each frame lasts `1 / 24` second. the manifest records the seed, dimensions, frame count, rate, and timing rule. the pixels are synthetic: bitmap text, flat UI shapes, a moving cursor-like mark, and moving color gradients. its colors and layout are benchmark inputs, not approved product artwork. no screen content is read.

the "mixed" profile remains the default and preserves the original composite fixture. three focused profiles isolate visual stresses:

- "mostly-static-ui": fine text and mostly static controls with a one-pixel moving caret;
- "fast-scrolling": repeated text rows moving five pixels per frame;
- "high-motion-gradient-cursor": a rapidly changing gradient field and fast cursor motion.

generate all four full reference fixtures from the repository root. each destination must be new:

```sh
python3 Benchmarks/generate_fixture.py --output Benchmarks/generated/mixed-640x360 --width 640 --height 360 --seed 7 --frames 240 --profile mixed
python3 Benchmarks/generate_fixture.py --output Benchmarks/generated/mostly-static-ui-640x360 --width 640 --height 360 --seed 7 --frames 240 --profile mostly-static-ui
python3 Benchmarks/generate_fixture.py --output Benchmarks/generated/fast-scrolling-640x360 --width 640 --height 360 --seed 7 --frames 240 --profile fast-scrolling
python3 Benchmarks/generate_fixture.py --output Benchmarks/generated/high-motion-gradient-cursor-640x360 --width 640 --height 360 --seed 7 --frames 240 --profile high-motion-gradient-cursor
```

to run the encoder candidates against each generated profile, give each run a new output directory:

```sh
python3 Benchmarks/run_encoder_benchmark.py --fixture Benchmarks/generated/mixed-640x360 --output Benchmarks/outputs/mixed-01 --runs 7
python3 Benchmarks/run_encoder_benchmark.py --fixture Benchmarks/generated/mostly-static-ui-640x360 --output Benchmarks/outputs/mostly-static-ui-01 --runs 7
python3 Benchmarks/run_encoder_benchmark.py --fixture Benchmarks/generated/fast-scrolling-640x360 --output Benchmarks/outputs/fast-scrolling-01 --runs 7
python3 Benchmarks/run_encoder_benchmark.py --fixture Benchmarks/generated/high-motion-gradient-cursor-640x360 --output Benchmarks/outputs/high-motion-gradient-cursor-01 --runs 7
```

generated frames, GIFs, and reports belong under the ignored "Benchmarks/generated/" and "Benchmarks/outputs/" directories. do not commit those bulk outputs; keep small reviewed summaries and representative comparisons when they exist. for a quick smoke run, use `--frames 6 --width 320 --height 180` with a different new output directory. keep the same seed, dimensions, and frame count for every candidate in one comparison.

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

the runner creates the requested synthetic fixture once, records one first-invocation sample and seven warm samples per available path, and alternates path order. paths are `gifski`, `magick` with `-layers Optimize`, `magick-unoptimized`, the legacy ImageIO helper, the app's `ImageIOOriginalGIFEncoder` via `imageio-app`, and ImageIO followed by `gifsicle --optimize=3`. it discovers `gifski`, `magick`, and `gifsicle` from `PATH`, and compiles both ImageIO helpers with `xcrun swiftc`. missing or unbuildable tools are reported as unavailable in `summary.json`; the raw report records path requirements and missing tools. no tool is installed by the runner.

to benchmark the actual app candidate in isolation, run:

```sh
python3 Benchmarks/run_encoder_benchmark.py --fixture Benchmarks/generated/mixed-640x360 --output Benchmarks/outputs/mixed-imageio-app-01 --runs 7 --candidates imageio-app
```

`imageio-app` compiles `SessionWorkspaceStore.swift` and `OriginalGIFEncoder.swift` with a benchmark-only CLI wrapper. it does not run the full application or capture pipeline. `summary.json` records the build duration and binary/source checksums separately. sample elapsed time includes helper process launch, PNG decode, GIF encode, output validation, and cleanup, but excludes compilation and fixture generation. the wrapper supplies deterministic timestamps from the fixture's frame index and rate, and uses the app's cumulative-centisecond schedule and 512 mib output cap. to reuse one build across profile runs, pass its path with `--imageio-app-binary`; the legacy `imageio` row remains separate.

to name all six paths explicitly, use:

```sh
python3 Benchmarks/run_encoder_benchmark.py --fixture Benchmarks/generated/mixed-640x360 --output Benchmarks/outputs/mixed-matrix-01 --runs 7 --candidates gifski magick magick-unoptimized imageio imageio-app imageio-gifsicle
```

`gifski` pins quality 90 explicitly and `--no-sort` to preserve manifest order. the existing `magick` path retains its optimized command; `magick-unoptimized` runs the same input and delay configuration without `-layers Optimize`. ImageMagick's `-loop 0` follows the input frames so it applies to the output animation. the ImageIO→Gifsicle path runs as two stages, writes its intermediate GIF inside the per-run temporary workspace, and includes both stages in elapsed time and the total timeout. each successful final GIF is retained under `gifs/` for visual review.

all paths must pass GIF structure, dimensions, frame count, exact per-frame centisecond schedule, cumulative duration, and infinite-loop validation. `raw.json` contains exact argument arrays for each path and stage, per-stage and total elapsed times, CPU user/system time when obtainable, exit status, sampled peak workspace bytes, peak resident bytes when obtainable, stderr, and parsed GIF metadata for every attempted run. `summary.json` contains environment/tool provenance, manifest and frame-content checksums, availability and missing-tool reasons, median/p90 of successful warm runs, and the per-run size, frame count, duration, and frame delays. a failed, invalid, timed-out, wrong-dimension, wrong-frame-count, wrong-loop, wrong-per-frame-delay, or out-of-tolerance-duration run removes its partial GIF and workspace, remains in the reports, and is not counted in the statistic.

run the harness checks with `python3 -m unittest discover -s Benchmarks -p 'test_encoder_benchmark.py' -v`. for a quick real-encoder smoke test, use a new output directory with `--frames 6 --width 320 --height 180 --runs 1`; it does not provide a valid performance comparison.

the runner measures offline encoding and optimization. it does not measure screen capture, streaming encode, stop-to-preview latency, or visual quality. the ImageIO helper is a native comparison path, not the approved bundled CLI. this harness does not yet automate dither/quality setting sweeps or visual-quality scoring. GIF timing is quantized to centiseconds; each frame's delay must match the fixture schedule derived by rounding cumulative frame boundaries to the nearest centisecond, cumulative duration must be within 20 ms, and the output must loop forever. the high-motion gradient/cursor profile is the recommended first visual review for the later quality-floor gate because it stresses gradients, motion, and temporal dithering; also review static UI/text separately for legibility. workspace size is sampled every 20 ms and can miss short-lived files. memory uses macOS `/usr/bin/time -l` when allowed, then sampled `ps` as a fallback; a short run or restricted host can yield `null`. the tool binary and build still need an exact license, dependency, architecture, signature, and source audit before packaging. no result from this harness alone selects a release encoder.

the first full four-profile run of the app candidate, with commands, checksums, results, and limitations, is documented in [imageio-app-2026-10-24.md](imageio-app-2026-10-24.md). its raw reports and GIFs remain in ignored output directories on the benchmark machine.

the official `gifski` 1.34.0 release was later compared with that app helper across the same four profiles. see [gifski-1.34.0-2026-10-24.md](gifski-1.34.0-2026-10-24.md) for release provenance, invocation settings, sample results, and limitations; raw measurements and one representative GIF per path/profile remain ignored on the benchmark machine.
