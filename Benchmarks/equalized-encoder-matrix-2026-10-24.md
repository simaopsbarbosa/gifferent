# equal-work encoder matrix — 2026-10-24

## scope

these four completed runs compare three offline PNG-to-GIF paths: ImageMagick with `-layers Optimize` (`magick`), the same ImageMagick command without that optimization (`magick-unoptimized`), and the legacy native ImageIO helper (`imageio`). each profile used 640×360, 240 frames, 24 fps, seed 7, and a 10-second fixture. each path has one first-invocation sample and seven warm samples in alternating path order. the table reports the warm median and nearest-rank p90; output bytes were identical in all eight successful samples for each path/profile.

## results

| profile | path | warm median | warm p90 | output bytes |
| --- | --- | ---: | ---: | ---: |
| mixed | `magick` | 15.4754 s | 15.8283 s | 9,453,925 |
| mixed | `magick-unoptimized` | 5.7569 s | 6.0774 s | 8,370,417 |
| mixed | `imageio` | 0.9659 s | 1.0149 s | 2,595,223 |
| mostly-static-ui | `magick` | 26.8058 s | 26.9015 s | 14,094 |
| mostly-static-ui | `magick-unoptimized` | 4.4851 s | 4.5237 s | 1,152,138 |
| mostly-static-ui | `imageio` | 0.7217 s | 0.8965 s | 11,815 |
| fast-scrolling | `magick` | 15.0024 s | 17.1215 s | 1,144,705 |
| fast-scrolling | `magick-unoptimized` | 4.6216 s | 5.2413 s | 1,481,020 |
| fast-scrolling | `imageio` | 0.9352 s | 0.9581 s | 874,638 |
| high-motion-gradient-cursor | `magick` | 16.6011 s | 20.8674 s | 16,437,627 |
| high-motion-gradient-cursor | `magick-unoptimized` | 6.5870 s | 7.0095 s | 17,308,612 |
| high-motion-gradient-cursor | `imageio` | 1.1850 s | 1.4858 s | 11,174,716 |

ImageMagick optimization took longer than its unoptimized path in all four profiles. It also produced a larger mixed GIF and a much larger mostly-static UI GIF, but smaller fast-scrolling and high-motion GIFs. The ImageIO output was smallest in all four measured profiles. These are descriptive results for these exact inputs and settings, not a release recommendation.

## fixtures and checksums

| profile | manifest sha-256 | combined frame sha-256 |
| --- | --- | --- |
| mixed | `cd2a9ffb73a5908e221ae2fd0e28233b7a1ce426dee9f9b4239371c35b9c07e2` | `a2e07a4980e7b437bc1e44d6a9d8ff7f11c70126abaeeb9ad3a580ecd1143c9d` |
| mostly-static-ui | `6e2f785f8c29a9ca43cd1bbf91dd636e0405822c01438cb8a27ef1a7a35a28fa` | `d42ed02d552de0db283b9a2d720ac782b7b62dc8dd7c41817da0837b3ce71fc2` |
| fast-scrolling | `d31d28bcba4880b86dac358e81a87e466fe74631414db7e69528405338dc8eec` | `e0750bce46287c335993b3e2610505b0debe4f18fe7cfa25e700ff1cac850885` |
| high-motion-gradient-cursor | `8a90e5f8d09fe44045642bc1fb744d3865494ad8ede21e36b95ab06759f71c64` | `8436939cbc8b536dcc3ea3423669f4f0ccdda1dc14a75a3e5eee4b652b4c0c01` |

## measured commands

all commands ran from the repository root with `--runs 7 --candidates magick magick-unoptimized imageio --magick-diffusion-amount 100`. the four exact invocations were:

```sh
python3 Benchmarks/run_encoder_benchmark.py --fixture Benchmarks/generated/mixed-640x360 --output Benchmarks/outputs/equalized-mixed-20261024 --runs 7 --candidates magick magick-unoptimized imageio --magick-diffusion-amount 100
python3 Benchmarks/run_encoder_benchmark.py --fixture Benchmarks/generated/mostly-static-ui-640x360 --output Benchmarks/outputs/equalized-static-ui-20261024 --runs 7 --candidates magick magick-unoptimized imageio --magick-diffusion-amount 100
python3 Benchmarks/run_encoder_benchmark.py --fixture Benchmarks/generated/fast-scrolling-640x360 --output Benchmarks/outputs/equalized-fast-scrolling-20261024-rerun --runs 7 --candidates magick magick-unoptimized imageio --magick-diffusion-amount 100 --imageio-app-binary Benchmarks/outputs/equalized-mixed-20261024/tools/imageio_app_encode
python3 Benchmarks/run_encoder_benchmark.py --fixture Benchmarks/generated/high-motion-gradient-cursor-640x360 --output Benchmarks/outputs/equalized-high-motion-20261024-rerun --runs 7 --candidates magick magick-unoptimized imageio --magick-diffusion-amount 100 --imageio-app-binary Benchmarks/outputs/equalized-mixed-20261024/tools/imageio_app_encode
```

the ImageMagick executable was version 7.1.2-34, Q16-HDRI, arm64, sha-256 `324c185d0dead1cf7326e7f87743da28086dde0a00538b96d5cd320ed7543466`. the legacy ImageIO helper had sha-256 `609a4ba115d69a19db3b23dcd9f3d636196e16bdd53a75201e3e77b6d8e9ac7d`. the two ImageMagick paths used the same ordered inputs, per-frame delay schedule, Floyd–Steinberg dithering, 100% diffusion amount, 256-color palette, and loop setting; `magick` adds only `-layers Optimize`. `imageio` used the legacy helper with the same ordered inputs and fixture timing. the ImageIO validation helper had sha-256 `9593cc6126569ee4f80f951078b322323c9195ca003d775e549ed28a71328ad2` in all reports. the rerun profiles reused that exact validator binary from the mixed-profile output directory.

## comparability and limits

the reports share the same benchmark commit (`d5d68c8d3b567f26dde2d6c30e5e271ad7dd37d1`) and macOS 27.0.1, build 26A434, arm64, Xcode 27.1, build 27A9275. the Mac was on AC with Low Power Mode off. the approved reference is a MacBook Air M2 with 8 GB RAM, but the benchmark sandbox denied `sysctl` reads for model, chip, and memory. `pmset -g therm` could not provide thermal or CPU power telemetry, so the thermal state is unknown.

each path includes its encoding/optimization work, the same ImageIO metadata-validation pass, the same structural and fixture-contract validation, and cleanup in measured elapsed time. all 24 runs per profile (eight per path) passed validation: 640×360 logical dimensions, 240 frames, the expected per-frame centisecond schedule, 10-second duration, and infinite looping. each path produced one identical output checksum across its eight runs. Gifski and Gifsicle were unavailable in all four reports; no measurements are reported for them. the `imageio` row is the legacy helper, not the app's `imageio-app` encoder candidate.

peak resident memory and CPU measurements were unavailable for every measured sample. sampled temporary-workspace measurements are not a substitute for peak memory and may miss short-lived files. the harness validates GIF structure and metadata, not decoded visual fidelity or playback in destination apps. no visual-quality conclusion is made, and no release encoder is selected by this report.
