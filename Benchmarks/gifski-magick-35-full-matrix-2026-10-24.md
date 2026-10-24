# full available encoder matrix at 35% diffusion — 2026-10-24

## scope and result

this run compares five available encoder paths across all four published synthetic profiles on the designated reference machine. `imageio-gifsicle` was attempted by the runner but unavailable because `gifsicle` is not installed. no tools were installed. the matrix covers 640×360, 240 frames, 24 fps, seed 7, one first invocation plus seven warm invocations per available path. all 160 available outputs passed shared ImageIO metadata inspection and fixture-contract validation: dimensions, frame count, exact centisecond schedule, duration, and infinite looping. this validates GIF structure and metadata, not every frame's pixels or visual quality.

the comparison records complete encoder-to-GIF paths. Gifski used quality 90; ImageMagick used Floyd–Steinberg diffusion at the approved 35%, with either `-layers Optimize` or no layer optimization; ImageIO uses system ImageIO; `imageio-app` uses the app's `OriginalGIFEncoder`. these controls and algorithms are not equivalent. the table is performance and byte-size evidence only, not quality proof or encoder selection.

| profile | path | cold | warm median | warm p90 | bytes | output SHA-256 |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| mostly-static-ui | `gifski` 1.34.0 | 1.2043 s | 0.5743 s | 0.5799 s | 15,311 | `3beeaabc6e18589bbb6c5b00cc5e1794a66a4d4ca7a65db2e9596a609064a555` |
| mostly-static-ui | `magick` optimized, 35% | 24.5571 s | 24.8010 s | 26.3960 s | 30,017 | `c05c2c3d5c1e0c2e9762d976722bf74bb1fe4df3cf4637fdb01764f9c517f67a` |
| mostly-static-ui | `magick-unoptimized`, 35% | 4.5977 s | 4.6373 s | 5.1111 s | 1,343,849 | `e083afbd0532955093640578072febff49386293869e34b0e214574d16d54ae4` |
| mostly-static-ui | `imageio` | 0.9360 s | 0.7332 s | 0.7556 s | 11,815 | `79cbf85089cb8b64530472b91b715dd51e90690b00203935a0a07777ef3f4970` |
| mostly-static-ui | `imageio-app` | 0.7116 s | 0.7209 s | 0.7524 s | 11,815 | `79cbf85089cb8b64530472b91b715dd51e90690b00203935a0a07777ef3f4970` |
| mixed | `gifski` 1.34.0 | 0.8639 s | 0.8659 s | 0.9512 s | 1,745,722 | `dfaa0b7866643a993cdea6ad1a5d5d91e760a3a1bef1cd07f04466b07ced35b9` |
| mixed | `magick` optimized, 35% | 14.4699 s | 14.2585 s | 14.6632 s | 4,079,548 | `5486f3022b37c4ae9abfe9049d7d672da72a9e5c3b4d51f935e4b86ff509fe83` |
| mixed | `magick-unoptimized`, 35% | 5.6680 s | 5.3451 s | 5.5799 s | 4,360,444 | `de225acfddeee20ed3f61b034e7aa9ee5daf52efb4fcfcf8ae624b38a21929a3` |
| mixed | `imageio` | 1.2436 s | 0.9286 s | 0.9749 s | 2,595,223 | `37aa47e79bf02f91f83bf0bc92974b14ce745fc5636e24f1aa32ccd653abd36f` |
| mixed | `imageio-app` | 0.9641 s | 0.9154 s | 0.9826 s | 2,595,223 | `37aa47e79bf02f91f83bf0bc92974b14ce745fc5636e24f1aa32ccd653abd36f` |
| fast-scrolling | `gifski` 1.34.0 | 0.6887 s | 0.7099 s | 0.7410 s | 909,046 | `597db1b092d1351c1b482160fefb36a85a128bc3aca4808feb7e8cd7bb1871a9` |
| fast-scrolling | `magick` optimized, 35% | 14.9902 s | 14.5009 s | 15.1221 s | 1,207,910 | `408dbb59da42606c4354e34d2fcc17f5ca4c9d0463b96db412e48fbbe7a7bcda` |
| fast-scrolling | `magick-unoptimized`, 35% | 4.5357 s | 4.6931 s | 4.8304 s | 1,672,572 | `ce211aeba8b4892f1cc6c30afe04bcaba7ff72862c554ffd3819bf7948715062` |
| fast-scrolling | `imageio` | 1.3316 s | 0.9321 s | 0.9509 s | 874,638 | `4194a5f956c9817af2bfa35a021aa346e20a70a713178752aa041f38c71476d8` |
| fast-scrolling | `imageio-app` | 0.9052 s | 0.9185 s | 0.9290 s | 874,638 | `4194a5f956c9817af2bfa35a021aa346e20a70a713178752aa041f38c71476d8` |
| high-motion-gradient-cursor | `gifski` 1.34.0 | 1.0581 s | 1.1570 s | 1.2687 s | 5,792,443 | `f4afa4f9e61d7b094cf6037f997c1a268b81fd85457a035a35032175f91efa1a` |
| high-motion-gradient-cursor | `magick` optimized, 35% | 16.3954 s | 16.1310 s | 20.5170 s | 9,524,098 | `e69ea343db4da5f0eda75b4aef35db7dd91edf8347ad128433b1eace8a288830` |
| high-motion-gradient-cursor | `magick-unoptimized`, 35% | 6.1138 s | 5.9959 s | 6.3762 s | 12,263,510 | `2665d4e3b43b817f6458b42076f7f147feb554d19e0005cc90f2e857330b2a4f` |
| high-motion-gradient-cursor | `imageio` | 1.3043 s | 1.1639 s | 1.2245 s | 11,174,716 | `48ed3ac05798146230ddfb80964d504819afdb0f3fb705f017fae88f3d642784` |
| high-motion-gradient-cursor | `imageio-app` | 1.1590 s | 1.1138 s | 1.1438 s | 11,174,716 | `48ed3ac05798146230ddfb80964d504819afdb0f3fb705f017fae88f3d642784` |

the runner's median and nearest-rank p90 use the seven successful warm samples. each available path/profile had eight successful samples and one output hash across all runs. the hash column is that shared cold/warm output hash. no candidate path failed validation. `imageio-gifsicle` was unavailable for each profile with `missing: gifsicle`. the first invocation is the first run in this series; operating-system caches were not flushed. the complete cold and warm per-sample records are preserved in the [static](results/gifski-magick-35-full-matrix-2026-10-24/static-summary.json), [mixed](results/gifski-magick-35-full-matrix-2026-10-24/mixed-summary.json), [fast-scrolling](results/gifski-magick-35-full-matrix-2026-10-24/fast-scrolling-summary.json), and [high-motion](results/gifski-magick-35-full-matrix-2026-10-24/high-motion-summary.json) JSON snapshots; larger `raw.json` logs remain under `/private/tmp`.

## provenance and measurement limits

- checkout commit: `3d849d5` (`docs: add visual encoder review samples`). fixture manifest and frame-content SHA-256 values are in the table below and each raw `summary.json`.
- Gifski: official 1.34.0 source commit `1060eab4500a20f27e2fa3ab7e85473d0e921cbd`, arm64 release binary SHA-256 `947969d778a894e9b2c281bc96c6644ba88a16aba6e64b3cd2a4f5e219d8de46`; command uses `--fps 24 --quality 90 --repeat 0 --no-sort`.
- ImageMagick: installed Homebrew ImageMagick 7.1.2-34 Q16-HDRI arm64, binary SHA-256 `324c185d0dead1cf7326e7f87743da28086dde0a00538b96d5cd320ed7543466`. both Magick paths use per-input centisecond delays, `-dither FloydSteinberg`, `-define dither:diffusion-amount=35%`, `-colors 256`, and `-loop 0`; optimized `magick` additionally uses `-layers Optimize`.
- legacy ImageIO helper SHA-256: `609a4ba115d69a19db3b23dcd9f3d636196e16bdd53a75201e3e77b6d8e9ac7d` (compiled for each output directory; same binary checksum each time).
- app ImageIO helper was compiled once with Xcode 27.1 `xcrun swiftc` in the first profile, then reused for the remaining three. arm64 helper SHA-256: `9f7d671b12f10f032231a03bee5ad66ac6361fe1a376fd3b03fa434539e8f31d`. its source file hashes are recorded in the first profile's `summary.json`; `otool -L` lists system frameworks and Swift runtime libraries.
- system: macOS 27.0.1 build 26A434, Xcode 27.1 build 27A9275, AC power, Low Power Mode off. the project-approved reference is Mac14,2 / M2 / 8 GB, but `sysctl` probes for model, chip, and memory were denied during this run; that machine identity was not independently confirmed here. thermal telemetry was unavailable.
- CPU and resident-memory metrics are unavailable. `/usr/bin/time -l /usr/bin/true` exited 1 with `time: sysctl kern.clockrate: Operation not permitted`; the sampled `ps` fallback also returned no RSS values. CPU fields are null. do not infer CPU or RSS from elapsed time. the harness's sampled peak workspace bytes matched the output file size for these samples, so it does not add an independent memory measurement. workspace polling occurs every 20 ms and may miss short-lived files.
- Gifski's AGPL-3.0-or-later source/dependency notice review is still open, including missing standalone `gif-dispose` notice text; the built candidate has not been selected or bundled. the Homebrew ImageMagick binary and its delegates/libraries are also not distribution-cleared. see the [Gifski source and license audit](gifski-1.34.0-build-audit-2026-10-24.md).

the runner's `peak_workspace_bytes_sampled` equaled each output GIF's byte size for every sample, so it reported no additional temporary-workspace storage beyond that GIF. the full output directories also contain fixture frames, metadata, retained outputs, compiled helpers, and the raw and summary records:

| profile | full output directory bytes | retained candidate GIF bytes | largest sampled path workspace bytes |
| --- | ---: | ---: | ---: |
| mostly-static-ui | 84,835,628 | 1,412,807 | 1,343,849 |
| mixed | 61,243,759 | 15,376,160 | 4,360,444 |
| fast-scrolling | 49,796,461 | 5,538,804 | 1,672,572 |
| high-motion-gradient-cursor | 95,241,256 | 49,929,483 | 12,263,510 |

directory totals are exact regular-file byte sums at report time and exclude the adjacent runner log. workspace size is a sampled temporary-file tree measurement, not process memory.

| profile | fixture manifest SHA-256 | frame-set SHA-256 |
| --- | --- | --- |
| mostly-static-ui | `6e2f785f8c29a9ca43cd1bbf91dd636e0405822c01438cb8a27ef1a7a35a28fa` | `d42ed02d552de0db283b9a2d720ac782b7b62dc8dd7c41817da0837b3ce71fc2` |
| mixed | `cd2a9ffb73a5908e221ae2fd0e28233b7a1ce426dee9f9b4239371c35b9c07e2` | `a2e07a4980e7b437bc1e44d6a9d8ff7f11c70126abaeeb9ad3a580ecd1143c9d` |
| fast-scrolling | `d31d28bcba4880b86dac358e81a87e466fe74631414db7e69528405338dc8eec` | `e0750bce46287c335993b3e2610505b0debe4f18fe7cfa25e700ff1cac850885` |
| high-motion-gradient-cursor | `8a90e5f8d09fe44045642bc1fb744d3865494ad8ede21e36b95ab06759f71c64` | `8436939cbc8b536dcc3ea3423669f4f0ccdda1dc14a75a3e5eee4b652b4c0c01` |

## commands and raw results

the four exact runner invocations were:

```sh
PATH=/private/tmp/gifski-target-1.34.0/release:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin python3 Benchmarks/run_encoder_benchmark.py --output /private/tmp/gifferent-fullmatrix-gifski-magick35-static-20261024 --frames 240 --width 640 --height 360 --seed 7 --profile mostly-static-ui --runs 7 --candidates gifski magick magick-unoptimized imageio imageio-app imageio-gifsicle --magick-diffusion-amount 35
PATH=/private/tmp/gifski-target-1.34.0/release:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin python3 Benchmarks/run_encoder_benchmark.py --output /private/tmp/gifferent-fullmatrix-gifski-magick35-mixed-20261024 --frames 240 --width 640 --height 360 --seed 7 --profile mixed --runs 7 --candidates gifski magick magick-unoptimized imageio imageio-app imageio-gifsicle --magick-diffusion-amount 35 --imageio-app-binary /private/tmp/gifferent-fullmatrix-gifski-magick35-static-20261024/tools/imageio_app_encode
PATH=/private/tmp/gifski-target-1.34.0/release:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin python3 Benchmarks/run_encoder_benchmark.py --output /private/tmp/gifferent-fullmatrix-gifski-magick35-fast-scrolling-20261024 --frames 240 --width 640 --height 360 --seed 7 --profile fast-scrolling --runs 7 --candidates gifski magick magick-unoptimized imageio imageio-app imageio-gifsicle --magick-diffusion-amount 35 --imageio-app-binary /private/tmp/gifferent-fullmatrix-gifski-magick35-static-20261024/tools/imageio_app_encode
PATH=/private/tmp/gifski-target-1.34.0/release:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin python3 Benchmarks/run_encoder_benchmark.py --output /private/tmp/gifferent-fullmatrix-gifski-magick35-high-motion-20261024 --frames 240 --width 640 --height 360 --seed 7 --profile high-motion-gradient-cursor --runs 7 --candidates gifski magick magick-unoptimized imageio imageio-app imageio-gifsicle --magick-diffusion-amount 35 --imageio-app-binary /private/tmp/gifferent-fullmatrix-gifski-magick35-static-20261024/tools/imageio_app_encode
```

the first profile compiled the app helper; that same binary was reused for the other three runs. the harness records exact candidate invocations in each `raw.json`. benchmark output directories, fixture frames, retained GIFs, and full `raw.json` logs remain outside Git. the four compact `summary.json` snapshots are preserved in the repository:

- `/private/tmp/gifferent-fullmatrix-gifski-magick35-static-20261024/`
- `/private/tmp/gifferent-fullmatrix-gifski-magick35-mixed-20261024/`
- `/private/tmp/gifferent-fullmatrix-gifski-magick35-fast-scrolling-20261024/`
- `/private/tmp/gifferent-fullmatrix-gifski-magick35-high-motion-20261024/`

the existing [visual review samples](reviews/gifski-magick-35-2026-10-24/index.html) cover only the mostly-static and high-motion paths. the approved visual floor still requires architect review; no visual review or encoder selection is made by this full matrix.

## conclusion

this matrix establishes repeatable timing, output size, and required structural metadata for five available paths on the designated machine. it does not establish visual quality, full release dependency clearance, memory or CPU targets, or an encoder choice. the definition-of-done CPU and memory measurements remain incomplete. no encoder is selected.
