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

the speed goals in [vision.md](../vision.md) remain targets until runs on an agreed reference Mac and fixture set establish them. the architect approved the minimum visual quality floor in [decisions.md](../decisions.md); representative samples still need review against it.

## exploratory encoder run

on the [reference Mac](environment.md), run one command from the repository root. the output directory must not exist yet:

```sh
python3 Benchmarks/run_encoder_benchmark.py --output Benchmarks/outputs/reference-640x360-01 --frames 240 --width 640 --height 360 --runs 7
```

ImageMagick paths use a Floyd–Steinberg diffusion amount of 100% by default, preserving the setting used in existing exploratory results. to run a controlled value from 0 to 100%, pass `--magick-diffusion-amount 35`; the runner rejects values outside that range. the selected percentage is recorded in `raw.json`, `summary.json`, and each ImageMagick command.

the runner creates the requested synthetic fixture once, records one first-invocation sample and seven warm samples per available path, and alternates path order on each round. the first invocation is labeled `cold`, but the harness does not flush operating-system caches. by default it runs the five-path primary comparison: `gifski`, `magick` with `-layers Optimize`, `magick-unoptimized`, the legacy ImageIO helper, and ImageIO followed by `gifsicle --optimize=3`. the app's `ImageIOOriginalGIFEncoder` via `imageio-app` is an optional sixth comparison because it is a distinct in-process app implementation rather than one of the five paths in the published CLI comparison. it discovers `gifski`, `magick`, and `gifsicle` from `PATH`, and compiles both ImageIO helpers with `xcrun swiftc`. missing or unbuildable tools are reported as unavailable in `summary.json` with the missing executable named; no tool is installed by the runner.

to benchmark the actual app candidate in isolation, run:

```sh
python3 Benchmarks/run_encoder_benchmark.py --fixture Benchmarks/generated/mixed-640x360 --output Benchmarks/outputs/mixed-imageio-app-01 --runs 7 --candidates imageio-app
```

`imageio-app` compiles `SessionWorkspaceStore.swift`, `GIFEditModel.swift`, and `OriginalGIFEncoder.swift` with a benchmark-only CLI wrapper. it does not run the full application or capture pipeline. `summary.json` records the build duration and binary/source checksums separately. sample elapsed time includes helper process launch, PNG decode, GIF encode, the app encoder's `GIFMetadataInspector` pass, shared structural and fixture-contract validation, and cleanup, but excludes compilation and fixture generation. the wrapper supplies deterministic timestamps from the fixture's frame index and rate, and uses the app's cumulative-centisecond schedule and 512 mib output cap. to reuse one build across profile runs, pass its path with `--imageio-app-binary`; the legacy `imageio` row remains separate.

the same compiled helper is required for every candidate path. after encoding (and after Gifsicle optimization, when selected), the harness invokes `imageio_app_encode --validate output.gif`, which runs the same per-frame ImageIO metadata inspection used by the app encoder. `imageio-app` already performs that inspection during encoding and does not run it a second time. the shared Python parser then applies the same GIF structure, dimensions, frame count, delay schedule, duration, and infinite-loop checks to every candidate. this equalizes the timed metadata-inspection work; it does not decode every frame's pixels or assess visual quality. validation and encoding stages both count toward end-to-end time and timeout.

to include the optional app implementation alongside all five primary paths, use:

```sh
python3 Benchmarks/run_encoder_benchmark.py --fixture Benchmarks/generated/mixed-640x360 --output Benchmarks/outputs/mixed-matrix-01 --runs 7 --candidates gifski magick magick-unoptimized imageio imageio-app imageio-gifsicle
```

`gifski` pins quality 90 explicitly and `--no-sort` to preserve manifest order. the existing `magick` path retains its optimized command; `magick-unoptimized` runs the same input and delay configuration without `-layers Optimize`. ImageMagick's `-loop 0` follows the input frames so it applies to the output animation. the ImageIO→Gifsicle path runs as two stages, writes its intermediate GIF inside the per-run temporary workspace, and includes both stages in elapsed time and the total timeout. each successful output is SHA-256 hashed. the first output with a new hash per candidate is retained under `gifs/` for visual review; identical later outputs from that candidate are removed after validation. every successful sample records its hash, byte count, and retained-output path (or `null`) in both reports.

all paths must pass the shared ImageIO metadata inspection plus GIF structure, dimensions, frame count, exact per-frame centisecond schedule, cumulative duration, and infinite-loop validation. `raw.json` contains exact argument arrays for each path and stage, per-stage and total elapsed times, CPU user/system time when obtainable, exit status, sampled peak workspace bytes, peak resident bytes when obtainable, stderr, and parsed GIF metadata for every attempted run. `summary.json` contains environment/tool provenance, manifest and frame-content checksums, availability and missing-tool reasons, median/p90 of successful warm runs, and the per-run cold/warm label, round, total and component timing, CPU, RSS and temporary-workspace measurements, output hash/size, retention status/path, dimensions, frame count, duration, frame delays, and loop value. it also keeps per-stage measurements for multi-stage paths. a failed, invalid, timed-out, wrong-dimension, wrong-frame-count, wrong-loop, wrong-per-frame-delay, or out-of-tolerance-duration run removes its partial GIF and workspace, remains in the reports, and is not counted in the statistic.

run the harness checks with `python3 -m unittest discover -s Benchmarks -p 'test_encoder_benchmark.py' -v`. for a quick real-encoder smoke test, use a new output directory with `--frames 6 --width 320 --height 180 --runs 1`; it does not provide a valid performance comparison.

the runner measures offline encoding and optimization. it does not measure screen capture, streaming encode, stop-to-preview latency, or visual quality. the ImageIO helper is a native comparison path, not the approved bundled CLI. its metadata inspection checks ImageIO's per-frame properties; it does not force full pixel decoding. this harness does not yet automate dither/quality setting sweeps or visual-quality scoring. GIF timing is quantized to centiseconds; each frame's delay must match the fixture schedule derived by rounding cumulative frame boundaries to the nearest centisecond, cumulative duration must be within 20 ms, and the output must loop forever. the high-motion gradient/cursor profile is the recommended first visual review for the later quality-floor gate because it stresses gradients, motion, and temporal dithering; also review static UI/text separately for legibility. workspace size is sampled every 20 ms and can miss short-lived files. memory uses macOS `/usr/bin/time -l` when allowed, then sampled `ps` as a fallback; a short run or restricted host can yield `null`. the tool binary and build still need an exact license, dependency, architecture, signature, and source audit before packaging. no result from this harness alone selects a release encoder.

the first full four-profile run of the app candidate, with commands, checksums, results, and limitations, is documented in [imageio-app-2026-10-24.md](imageio-app-2026-10-24.md). its raw reports and GIFs remain in ignored output directories on the benchmark machine.

the official `gifski` 1.34.0 release was later compared with that app helper across the same four profiles. see [gifski-1.34.0-2026-10-24.md](gifski-1.34.0-2026-10-24.md) for release provenance, invocation settings, sample results, and limitations; raw measurements and one representative GIF per path/profile remain ignored on the benchmark machine.

the equal-work ImageMagick and legacy ImageIO results across all four synthetic profiles are summarized in [equalized-encoder-matrix-2026-10-24.md](equalized-encoder-matrix-2026-10-24.md). the report includes fixture checksums, exact commands, timing and output-size measurements, and validation limits; no visual-quality or release-selection claim is made.

a limited representative-frame visual spot check for the static-UI and high-motion profiles is available in [the equal-work review](reviews/equalized-encoder-2026-10-24/index.html), with provenance and limits in its [review notes](reviews/equalized-encoder-2026-10-24/README.md). optimized ImageMagick at 100% diffusion shows faint speckling in flat dark UI regions at native size, more visible at 2×; this is awaiting architect classification against the approved quality floor. still frames do not establish flicker or temporal quality, and the review does not select an encoder.

the app exposes per-recording diagnostics only in memory for tests and local engineering inspection. `accepted` counts frames with nonnegative, strictly increasing timestamps offered to the bounded stream, including frames later displaced by its newest-frame policy; `dropped` is the displaced subset, and `rejectedTimestamps` counts invalid or non-increasing timestamps. ScreenCaptureKit samples that the callback ignores before offering a frame are not included. counts are snapshotted after the stream closes and the frame consumer drains, so they remain available after finalization. `startToRecording` runs from the coordinator's accepted start request to its transition into recording. `stopToCapturedSession` ends after frame drain and workspace finalization. `stopToPreviewReady` runs from the first stop request through frame drain, workspace finalization, GIF encoding, metadata validation, and committing the preview output, ending at the coordinator's `.previewReady` transition. failed starts have no start-to-recording duration; failed or cancelled preview preparation has no stop-to-preview-ready duration. all durations use a monotonic clock. these diagnostics contain no pixels, are not persisted, and are not uploaded; they do not measure the time for the preview window to become visible on screen.
