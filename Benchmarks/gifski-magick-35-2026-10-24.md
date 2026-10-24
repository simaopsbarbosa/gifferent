# focused gifski and ImageMagick comparison at 35% diffusion — 2026-10-24

## scope and result

this is a four-profile comparison of the pinned [Gifski 1.34.0 source build](gifski-1.34.0-build-audit-2026-10-24.md) and the installed ImageMagick CLI at the architect-approved 35% diffusion setting. it covers two encoder paths across all four fixture profiles, not the full multi-path encoder matrix; it is not a quality assessment or encoder selection. all paths received 640×360, 240-frame, 24 fps synthetic fixtures. mostly-static-ui and high-motion-gradient-cursor each had one cold invocation and seven warm invocations; mixed and fast-scrolling each had one cold invocation and four warm invocations. all 52 outputs passed shared per-frame metadata inspection and fixture-contract validation: 640×360, 240 frames, 10.0 seconds, expected centisecond schedule, and infinite looping.

| profile | path | cold | warm median | warm p90 | output bytes |
| --- | --- | ---: | ---: | ---: | ---: |
| mostly-static-ui | `gifski` 1.34.0 | 0.8096 s | 0.5861 s | 0.6143 s | 15,311 |
| mostly-static-ui | `magick` optimized, 35% | 23.7848 s | 24.4595 s | 27.0307 s | 30,017 |
| high-motion-gradient-cursor | `gifski` 1.34.0 | 1.1928 s | 1.0630 s | 1.5583 s | 5,792,443 |
| high-motion-gradient-cursor | `magick` optimized, 35% | 15.9294 s | 16.6909 s | 17.4592 s | 9,524,098 |
| mixed | `gifski` 1.34.0 | 1.6405 s | 0.8597 s | 0.8951 s | 1,745,722 |
| mixed | `magick` optimized, 35% | 14.1604 s | 13.5106 s | 13.5840 s | 4,079,548 |
| fast-scrolling | `gifski` 1.34.0 | 0.9029 s | 0.6787 s | 0.7445 s | 909,046 |
| fast-scrolling | `magick` optimized, 35% | 14.3579 s | 14.1965 s | 14.4812 s | 1,207,910 |

all outputs per path/profile had the same checksum. median and nearest-rank p90 use the available warm samples (seven for the first two profiles, four for the latter two). the benchmark records timing and byte size; it does not show that one output is visually better. the approved quality floor still requires visual review at native and 2× scale, especially for static text, gradients, temporal noise, and cursor edges. no frame-by-frame visual review was performed here.

## provenance and environment

- Gifski source commit: `1060eab4500a20f27e2fa3ab7e85473d0e921cbd`; built with Rust/Cargo 1.85.0, default CLI features, `--release --locked`, no video feature. binary SHA-256: `947969d778a894e9b2c281bc96c6644ba88a16aba6e64b3cd2a4f5e219d8de46`.
- ImageMagick: 7.1.2-34 Q16-HDRI arm64 from `/opt/homebrew/Cellar/imagemagick/7.1.2-34/bin/magick`; binary SHA-256 `324c185d0dead1cf7326e7f87743da28086dde0a00538b96d5cd320ed7543466`. this is the installed Homebrew build, not a proposed bundled build.
- system: macOS 27.0.1 build 26A434, Xcode 27.1 build 27A9275, AC power, Low Power Mode off. `sysctl` probes for model, chip, and memory were denied; thermal telemetry was also unavailable, so this run could not independently confirm the approved Mac model/memory or thermal state. CPU and peak resident memory readings are null.
- Gifski linked only `/usr/lib/libiconv.2.dylib` and `/usr/lib/libSystem.B.dylib`. The installed Magick binary links Homebrew `MagickCore`, `MagickWand`, `lcms2`, `freetype`, and `libltdl`, plus system `libxml2`, `libbz2`, `libz`, `libSystem`, and `libc++`; that inventory is not a bundle license audit.
- fixture manifest SHA-256: static UI `6e2f785f8c29a9ca43cd1bbf91dd636e0405822c01438cb8a27ef1a7a35a28fa`; high-motion `8a90e5f8d09fe44045642bc1fb744d3865494ad8ede21e36b95ab06759f71c64`.
- fixture manifest SHA-256: mixed `cd2a9ffb73a5908e221ae2fd0e28233b7a1ce426dee9f9b4239371c35b9c07e2`; fast-scrolling `d31d28bcba4880b86dac358e81a87e466fe74631414db7e69528405338dc8eec`. frame-set SHA-256 values are recorded in the corresponding summary JSON files.
- harness outputs and exact raw samples are outside the repository: `/private/tmp/gifferent-gifski-magick35-static-20261024/{raw.json,summary.json}`, `/private/tmp/gifferent-gifski-magick35-motion-20261024/{raw.json,summary.json}`, `/private/tmp/gifferent-gifski-magick35-mixed-20261024/{raw.json,summary.json}`, and `/private/tmp/gifferent-gifski-magick35-fast-scrolling-20261024/{raw.json,summary.json}`. one representative GIF per path/profile is also retained in those output trees.

the runner timed the complete path: encoder invocation plus shared ImageIO metadata inspection, structural and fixture checks, and cleanup. metadata validation reads frame properties; it does not decode every frame's pixels. ImageMagick's exact command includes per-input centisecond delays, `-define dither:diffusion-amount=35%`, `-colors 256`, `-layers Optimize`, and `-loop 0`. Gifski uses `--fps 24 --quality 90 --repeat 0 --no-sort`. the two encoders' quality controls are not equivalent.

## commands

the build command and temporary toolchain environment are recorded in the [source/build audit](gifski-1.34.0-build-audit-2026-10-24.md). these harness commands ran from the gifferent checkout; outputs and generated frames stayed under `/private/tmp`:

```sh
PATH=/private/tmp/gifski-target-1.34.0/release:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin python3 Benchmarks/run_encoder_benchmark.py --output /private/tmp/gifferent-gifski-magick35-static-20261024 --frames 240 --width 640 --height 360 --seed 7 --profile mostly-static-ui --runs 7 --candidates gifski magick --magick-diffusion-amount 35
PATH=/private/tmp/gifski-target-1.34.0/release:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin python3 Benchmarks/run_encoder_benchmark.py --output /private/tmp/gifferent-gifski-magick35-motion-20261024 --frames 240 --width 640 --height 360 --seed 7 --profile high-motion-gradient-cursor --runs 7 --candidates gifski magick --magick-diffusion-amount 35
PATH=/private/tmp/gifski-target-1.34.0/release:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin python3 Benchmarks/run_encoder_benchmark.py --output /private/tmp/gifferent-gifski-magick35-mixed-20261024 --frames 240 --width 640 --height 360 --seed 7 --profile mixed --runs 4 --candidates gifski magick --magick-diffusion-amount 35
PATH=/private/tmp/gifski-target-1.34.0/release:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin python3 Benchmarks/run_encoder_benchmark.py --output /private/tmp/gifferent-gifski-magick35-fast-scrolling-20261024 --frames 240 --width 640 --height 360 --seed 7 --profile fast-scrolling --runs 4 --candidates gifski magick --magick-diffusion-amount 35
```

the focused benchmark uses the existing harness implementation and did not modify app code or candidate behavior. `python3 -m unittest discover -s Benchmarks -p 'test_encoder_benchmark.py' -v` passed all 37 benchmark-harness tests.

## remaining evidence

- visually inspect representative and matching frames at 1× and 2× against the approved floor; this report makes no quality claim.
- rerun on a verified baseline Mac when model, memory, and thermal probes are available if those environmental fields are required for the published baseline.
- complete the full multi-path matrix before comparing release candidates. include memory and CPU measurements if the host permits them.
- resolve complete license and notice texts for the 47 active Gifski dependencies, including the missing standalone `gif-dispose` license/notice text, before any packaging decision. no encoder is selected.
