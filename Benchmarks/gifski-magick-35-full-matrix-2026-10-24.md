# full available encoder matrix at 35% diffusion — 2026-10-24

## scope and result

this run compares five available encoder paths across all four published synthetic profiles on the designated reference machine. `imageio-gifsicle` was attempted by the runner but unavailable because `gifsicle` is not installed. no tools were installed. the matrix covers 640×360, 240 frames, 24 fps, seed 7, one cold invocation plus seven warm invocations per available path. all 160 available outputs passed shared ImageIO metadata inspection and fixture-contract validation: dimensions, frame count, exact centisecond schedule, duration, and infinite looping. this validates GIF structure and metadata, not every frame’s pixels or visual quality.

the comparison records complete encoder-to-GIF paths. Gifski used quality 90; ImageMagick used Floyd–Steinberg diffusion at the approved 35%, with either `-layers Optimize` or no layer optimization; ImageIO uses system ImageIO; `imageio-app` uses the app’s `OriginalGIFEncoder`. these controls and algorithms are not equivalent. the tables are performance and byte-size evidence only, not quality proof or encoder selection.

| profile | path | cold | warm median | warm p90 | bytes | output SHA-256 |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| mostly-static-ui | `gifski` 1.34.0 | 0.624 s | 0.573 s | 0.591 s | 15,311 | `3beeaabc6e18589bbb6c5b00cc5e1794a66a4d4ca7a65db2e9596a609064a555` |
| mostly-static-ui | `magick` optimized, 35% | 24.143 s | 24.543 s | 24.966 s | 30,017 | `c05c2c3d5c1e0c2e9762d976722bf74bb1fe4df3cf4637fdb01764f9c517f67a` |
| mostly-static-ui | `magick-unoptimized`, 35% | 4.624 s | 4.621 s | 4.866 s | 1,343,849 | `e083afbd0532955093640578072febff49386293869e34b0e214574d16d54ae4` |
| mostly-static-ui | `imageio` | 0.976 s | 0.731 s | 0.742 s | 11,815 | `79cbf85089cb8b64530472b91b715dd51e90690b00203935a0a07777ef3f4970` |
| mostly-static-ui | `imageio-app` | 0.731 s | 0.711 s | 0.765 s | 11,815 | `79cbf85089cb8b64530472b91b715dd51e90690b00203935a0a07777ef3f4970` |
| mixed | `gifski` 1.34.0 | 0.864 s | 0.986 s | 1.239 s | 1,745,722 | `dfaa0b7866643a993cdea6ad1a5d5d91e760a3a1bef1cd07f04466b07ced35b9` |
| mixed | `magick` optimized, 35% | 13.435 s | 14.305 s | 17.090 s | 4,079,548 | `5486f3022b37c4ae9abfe9049d7d672da72a9e5c3b4d51f935e4b86ff509fe83` |
| mixed | `magick-unoptimized`, 35% | 5.100 s | 5.436 s | 5.648 s | 4,360,444 | `de225acfddeee20ed3f61b034e7aa9ee5daf52efb4fcfcf8ae624b38a21929a3` |
| mixed | `imageio` | 0.955 s | 0.956 s | 1.090 s | 2,595,223 | `37aa47e79bf02f91f83bf0bc92974b14ce745fc5636e24f1aa32ccd653abd36f` |
| mixed | `imageio-app` | 0.894 s | 0.947 s | 1.013 s | 2,595,223 | `37aa47e79bf02f91f83bf0bc92974b14ce745fc5636e24f1aa32ccd653abd36f` |
| fast-scrolling | `gifski` 1.34.0 | 0.720 s | 0.687 s | 0.897 s | 909,046 | `597db1b092d1351c1b482160fefb36a85a128bc3aca4808feb7e8cd7bb1871a9` |
| fast-scrolling | `magick` optimized, 35% | 14.627 s | 14.318 s | 14.636 s | 1,207,910 | `408dbb59da42606c4354e34d2fcc17f5ca4c9d0463b96db412e48fbbe7a7bcda` |
| fast-scrolling | `magick-unoptimized`, 35% | 4.535 s | 4.509 s | 4.629 s | 1,672,572 | `ce211aeba8b4892f1cc6c30afe04bcaba7ff72862c554ffd3819bf7948715062` |
| fast-scrolling | `imageio` | 1.294 s | 0.915 s | 0.991 s | 874,638 | `4194a5f956c9817af2bfa35a021aa346e20a70a713178752aa041f38c71476d8` |
| fast-scrolling | `imageio-app` | 0.905 s | 0.902 s | 0.914 s | 874,638 | `4194a5f956c9817af2bfa35a021aa346e20a70a713178752aa041f38c71476d8` |
| high-motion-gradient-cursor | `gifski` 1.34.0 | 1.031 s | 1.031 s | 1.050 s | 5,792,443 | `f4afa4f9e61d7b094cf6037f997c1a268b81fd85457a035a35032175f91efa1a` |
| high-motion-gradient-cursor | `magick` optimized, 35% | 15.531 s | 15.549 s | 15.827 s | 9,524,098 | `e69ea343db4da5f0eda75b4aef35db7dd91edf8347ad128433b1eace8a288830` |
| high-motion-gradient-cursor | `magick-unoptimized`, 35% | 5.725 s | 5.769 s | 5.831 s | 12,263,510 | `2665d4e3b43b817f6458b42076f7f147feb554d19e0005cc90f2e857330b2a4f` |
| high-motion-gradient-cursor | `imageio` | 1.332 s | 1.120 s | 1.303 s | 11,174,716 | `48ed3ac05798146230ddfb80964d504819afdb0f3fb705f017fae88f3d642784` |
| high-motion-gradient-cursor | `imageio-app` | 1.095 s | 1.100 s | 1.118 s | 11,174,716 | `48ed3ac05798146230ddfb80964d504819afdb0f3fb705f017fae88f3d642784` |

the runner’s median and nearest-rank p90 use the seven successful warm samples. every available path/profile had eight successful samples and one identical output hash across all runs. the hash column is that shared cold/warm output hash. no candidate path failed metadata or fixture-contract validation. `imageio-gifsicle` was unavailable for each profile with `missing: gifsicle`. the first invocation is the first run in this series; operating-system caches were not flushed. the complete per-sample cold and warm records, including contract metadata, CPU and RSS, are preserved in the [static](results/gifski-magick-35-full-matrix-2026-10-24/static-summary.json), [mixed](results/gifski-magick-35-full-matrix-2026-10-24/mixed-summary.json), [fast-scrolling](results/gifski-magick-35-full-matrix-2026-10-24/fast-scrolling-summary.json), and [high-motion](results/gifski-magick-35-full-matrix-2026-10-24/high-motion-summary.json) JSON snapshots. larger `raw.json` logs remain under `/private/tmp`.

## resource measurements

each candidate’s encoding and metadata-validation commands were timed separately with `/usr/bin/time -l`. CPU values below are medians of the seven warm samples, summing user and system CPU seconds reported for that path’s timed stages. peak RSS is the median and nearest-rank p90 across warm samples of the maximum RSS reported by any separately timed stage in that path (encoder or shared validator); `imageio-app` does its own validation inside its timed command. these are command-stage measurements, not the benchmark runner’s process RSS or an aggregate for the whole runner. RSS is the operating system’s maximum resident set for a timed command, not temporary-file workspace.

| profile | path | warm median user CPU | warm p90 user CPU | warm median system CPU | warm p90 system CPU | warm median peak RSS | warm p90 peak RSS |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| mostly-static-ui | `gifski` 1.34.0 | 3.030 s | 3.070 s | 0.210 s | 0.230 s | 79.7 MiB | 81.6 MiB |
| mostly-static-ui | `magick` optimized, 35% | 23.250 s | 23.550 s | 0.740 s | 0.800 s | 634.9 MiB | 669.8 MiB |
| mostly-static-ui | `magick-unoptimized`, 35% | 4.090 s | 4.130 s | 0.370 s | 0.390 s | 514.7 MiB | 574.3 MiB |
| mostly-static-ui | `imageio` | 0.640 s | 0.650 s | 0.080 s | 0.080 s | 432.2 MiB | 595.6 MiB |
| mostly-static-ui | `imageio-app` | 0.650 s | 0.680 s | 0.080 s | 0.090 s | 451.2 MiB | 550.1 MiB |
| mixed | `gifski` 1.34.0 | 4.950 s | 5.130 s | 0.310 s | 0.350 s | 82.8 MiB | 88.9 MiB |
| mixed | `magick` optimized, 35% | 12.660 s | 13.670 s | 1.220 s | 1.730 s | 1038.7 MiB | 1339.9 MiB |
| mixed | `magick-unoptimized`, 35% | 4.900 s | 5.060 s | 0.380 s | 0.410 s | 764.7 MiB | 1046.3 MiB |
| mixed | `imageio` | 0.860 s | 0.890 s | 0.090 s | 0.120 s | 581.5 MiB | 626.8 MiB |
| mixed | `imageio-app` | 0.860 s | 0.870 s | 0.090 s | 0.110 s | 627.4 MiB | 635.9 MiB |
| fast-scrolling | `gifski` 1.34.0 | 3.960 s | 3.990 s | 0.220 s | 0.230 s | 78.0 MiB | 81.6 MiB |
| fast-scrolling | `magick` optimized, 35% | 13.290 s | 13.470 s | 0.860 s | 0.890 s | 970.3 MiB | 997.2 MiB |
| fast-scrolling | `magick-unoptimized`, 35% | 4.110 s | 4.270 s | 0.290 s | 0.330 s | 814.6 MiB | 932.7 MiB |
| fast-scrolling | `imageio` | 0.840 s | 0.880 s | 0.070 s | 0.100 s | 626.8 MiB | 626.8 MiB |
| fast-scrolling | `imageio-app` | 0.840 s | 0.860 s | 0.070 s | 0.080 s | 629.3 MiB | 629.4 MiB |
| high-motion-gradient-cursor | `gifski` 1.34.0 | 5.700 s | 5.730 s | 0.440 s | 0.480 s | 79.7 MiB | 85.4 MiB |
| high-motion-gradient-cursor | `magick` optimized, 35% | 14.380 s | 14.460 s | 0.990 s | 1.030 s | 1002.4 MiB | 1152.7 MiB |
| high-motion-gradient-cursor | `magick-unoptimized`, 35% | 5.280 s | 5.330 s | 0.340 s | 0.380 s | 895.5 MiB | 997.6 MiB |
| high-motion-gradient-cursor | `imageio` | 1.000 s | 1.030 s | 0.090 s | 0.090 s | 626.8 MiB | 626.8 MiB |
| high-motion-gradient-cursor | `imageio-app` | 1.010 s | 1.030 s | 0.080 s | 0.080 s | 660.3 MiB | 660.3 MiB |

CPU seconds may exceed elapsed wall time for multithreaded tools. `/usr/bin/time -l /usr/bin/true` succeeded in this elevated run (`system_time_probe.exit_code=0`), and the report includes CPU and peak RSS only where the timed command supplied them. the harness’s `/usr/bin/time -p` fallback and wrapper-plus-descendants `ps` sampler were separately smoke-tested; the full matrix used `/usr/bin/time -l`. fallback sampling is periodic and may miss short-lived RSS peaks. neither method measures the benchmark runner/validator’s overall memory footprint.

## provenance and limits

- benchmark harness checkout commit: `bc98a1d` (`test: capture CPU with posix time fallback`).
- fixtures: seed 7, 640×360, 240 frames at 24 fps; manifest and frame-set SHA-256 values are below and repeated in each summary snapshot.
- Gifski: official 1.34.0 source commit `1060eab4500a20f27e2fa3ab7e85473d0e921cbd`, arm64 release binary SHA-256 `947969d778a894e9b2c281bc96c6644ba88a16aba6e64b3cd2a4f5e219d8de46`; command uses `--fps 24 --quality 90 --repeat 0 --no-sort`.
- ImageMagick: installed Homebrew ImageMagick 7.1.2-34 Q16-HDRI arm64, binary SHA-256 `324c185d0dead1cf7326e7f87743da28086dde0a00538b96d5cd320ed7543466`. both Magick paths use per-input centisecond delays, `-dither FloydSteinberg`, `-define dither:diffusion-amount=35%`, `-colors 256`, and `-loop 0`; optimized `magick` additionally uses `-layers Optimize`.
- legacy ImageIO helper SHA-256: `609a4ba115d69a19db3b23dcd9f3d636196e16bdd53a75201e3e77b6d8e9ac7d` (compiled for each output directory; same binary checksum each time).
- app ImageIO helper was compiled once with Xcode 27.1 `xcrun swiftc` in the first profile and reused for the other three. arm64 helper SHA-256: `9f7d671b12f10f032231a03bee5ad66ac6361fe1a376fd3b03fa434539e8f31d`; its source hashes and linked system libraries are in the first profile summary.
- system: macOS 27.0.1 build 26A434, Xcode 27.1 build 27A9275, AC power, Low Power Mode off. the project-approved reference is Mac14,2 / M2 / 8 GB, but `sysctl` probes for model, chip, and memory were denied; that machine identity was not independently confirmed. thermal telemetry was unavailable.
- Gifski’s AGPL-3.0-or-later source/dependency notice review remains open, including missing standalone `gif-dispose` notice text; the built candidate has not been selected or bundled. the Homebrew ImageMagick binary and its delegates/libraries are also not distribution-cleared. see the [Gifski source and license audit](gifski-1.34.0-build-audit-2026-10-24.md).

the benchmark runner samples temporary workspace every 20 ms, so a short-lived file may be missed. for the new runs, each profile’s reported workspace high-water mark is the largest sampled candidate work tree; it is not a memory metric. output directory sizes below are exact regular-file byte sums at report time and include fixture frames, retained outputs, helper binaries, work files, raw JSON, and summary JSON.

| profile | full output directory bytes | retained candidate GIF bytes | largest sampled path workspace bytes |
| --- | ---: | ---: | ---: |
| mostly-static-ui | 44,607,148 | 1,412,807 | 1,343,849 |
| mixed | 58,543,157 | 15,376,160 | 4,360,444 |
| fast-scrolling | 48,970,525 | 5,538,804 | 1,672,572 |
| high-motion-gradient-cursor | 93,273,997 | 49,929,483 | 12,263,510 |

| profile | fixture manifest SHA-256 | frame-set SHA-256 |
| --- | --- | --- |
| mostly-static-ui | `6e2f785f8c29a9ca43cd1bbf91dd636e0405822c01438cb8a27ef1a7a35a28fa` | `d42ed02d552de0db283b9a2d720ac782b7b62dc8dd7c41817da0837b3ce71fc2` |
| mixed | `cd2a9ffb73a5908e221ae2fd0e28233b7a1ce426dee9f9b4239371c35b9c07e2` | `a2e07a4980e7b437bc1e44d6a9d8ff7f11c70126abaeeb9ad3a580ecd1143c9d` |
| fast-scrolling | `d31d28bcba4880b86dac358e81a87e466fe74631414db7e69528405338dc8eec` | `e0750bce46287c335993b3e2610505b0debe4f18fe7cfa25e700ff1cac850885` |
| high-motion-gradient-cursor | `8a90e5f8d09fe44045642bc1fb744d3865494ad8ede21e36b95ab06759f71c64` | `8436939cbc8b536dcc3ea3423669f4f0ccdda1dc14a75a3e5eee4b652b4c0c01` |

## commands and raw results

the four runner invocations used the same 240-frame fixtures and seven warm runs. outputs went to fresh directories; the app helper built once in the static run was reused for the other profiles. `--fixture` points to the previously published fixture directory; each invocation also used `--magick-diffusion-amount 35` and the same candidate list shown below. the harness records exact tool invocations and metrics in each `raw.json` and `summary.json`.

```sh
PATH=/private/tmp/gifski-target-1.34.0/release:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin python3 Benchmarks/run_encoder_benchmark.py --output /private/tmp/gifferent-fullmatrix-resourced-static-20261024 --fixture /private/tmp/gifferent-fullmatrix-gifski-magick35-static-20261024/fixture --frames 240 --width 640 --height 360 --seed 7 --profile mostly-static-ui --runs 7 --candidates gifski magick magick-unoptimized imageio imageio-app imageio-gifsicle --magick-diffusion-amount 35
PATH=/private/tmp/gifski-target-1.34.0/release:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin python3 Benchmarks/run_encoder_benchmark.py --output /private/tmp/gifferent-fullmatrix-resourced-mixed-20261024 --fixture /private/tmp/gifferent-fullmatrix-gifski-magick35-mixed-20261024/fixture --frames 240 --width 640 --height 360 --seed 7 --profile mixed --runs 7 --candidates gifski magick magick-unoptimized imageio imageio-app imageio-gifsicle --magick-diffusion-amount 35 --imageio-app-binary /private/tmp/gifferent-fullmatrix-resourced-static-20261024/tools/imageio_app_encode
PATH=/private/tmp/gifski-target-1.34.0/release:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin python3 Benchmarks/run_encoder_benchmark.py --output /private/tmp/gifferent-fullmatrix-resourced-fast-scrolling-20261024 --fixture /private/tmp/gifferent-fullmatrix-gifski-magick35-fast-scrolling-20261024/fixture --frames 240 --width 640 --height 360 --seed 7 --profile fast-scrolling --runs 7 --candidates gifski magick magick-unoptimized imageio imageio-app imageio-gifsicle --magick-diffusion-amount 35 --imageio-app-binary /private/tmp/gifferent-fullmatrix-resourced-static-20261024/tools/imageio_app_encode
PATH=/private/tmp/gifski-target-1.34.0/release:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin python3 Benchmarks/run_encoder_benchmark.py --output /private/tmp/gifferent-fullmatrix-resourced-high-motion-20261024 --fixture /private/tmp/gifferent-fullmatrix-gifski-magick35-high-motion-20261024/fixture --frames 240 --width 640 --height 360 --seed 7 --profile high-motion-gradient-cursor --runs 7 --candidates gifski magick magick-unoptimized imageio imageio-app imageio-gifsicle --magick-diffusion-amount 35 --imageio-app-binary /private/tmp/gifferent-fullmatrix-resourced-static-20261024/tools/imageio_app_encode
```

the ephemeral raw data and retained GIF outputs remain under `/private/tmp/gifferent-fullmatrix-resourced-{static,mixed,fast-scrolling,high-motion}-20261024/`. the repository contains only the compact summary snapshots. the [visual review samples](reviews/gifski-magick-35-2026-10-24/index.html) cover only the mostly-static and high-motion profiles. the approved visual floor still requires architect review; no visual selection is made by this matrix.

## conclusion

this matrix establishes repeatable timing, output size, metadata validation, command-stage CPU, and command-stage peak RSS for five available paths on the intended reference setup, subject to the unconfirmed machine identity and stated measurement boundaries. it does not establish visual quality, full release dependency clearance, whole-runner memory, or an encoder choice. no encoder is selected.
