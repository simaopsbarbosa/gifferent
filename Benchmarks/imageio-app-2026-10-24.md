# imageio app candidate benchmark — 2026-10-24

## result

this run measured the app's `ImageIOOriginalGIFEncoder` through the benchmark-only `imageio-app` wrapper. each fixture was encoded sequentially with one first invocation and seven warm runs. all eight outputs per profile passed the harness checks for 640×360 dimensions, 240 frames, the expected per-frame centisecond schedule, 10.0-second total duration, and infinite looping.

| profile | warm median | warm p90 | first invocation | output size |
| --- | ---: | ---: | ---: | ---: |
| mixed | 0.8961 s | 0.9363 s | 0.9919 s | 2,595,223 bytes |
| mostly-static-ui | 0.7042 s | 0.7099 s | 0.8219 s | 11,815 bytes |
| fast-scrolling | 0.9021 s | 0.9106 s | 0.9430 s | 874,638 bytes |
| high-motion-gradient-cursor | 1.1248 s | 1.1630 s | 1.1882 s | 11,174,716 bytes |

each row has seven successful warm samples; the p90 uses the harness's nearest-rank summary. all eight outputs within each profile had the same byte size. these are measurements of offline PNG-to-GIF encoding, not screen recording, capture latency, stop-to-preview latency, or full-app responsiveness.

## machine and provenance

- reference system: MacBook Air Mac14,2, Apple M2, 8 GB RAM; macOS 27.0.1 build 26A434; Xcode 27.1 build 27A9275; arm64.
- power/thermal: on AC, Low Power Mode off. `pmset -g therm` did not provide thermal or CPU power telemetry on this host, so no thermal state is claimed.
- benchmark base revision: `6cd31848bd43ef6dca98e611df797d33370cefc2`. the benchmark wrapper and runner changes in this result were uncommitted during measurement and are included in the commit containing this report; candidate source hashes below pin what was actually compiled.
- candidate sources: `SessionWorkspaceStore.swift` `56dfbfe623aca502cc3242c8aa18b520934042db320db902ed84b647c9671106`; `OriginalGIFEncoder.swift` `d9f4e7b8e7282a90002a7dded7bd673239e85934ebc92d5d9ee8dfe0102e8aa1`; benchmark wrapper `imageio_app_encode.swift` `a2f688642936036b08100da2e451680f6d675ec56c0e123016917919529ab9e9`.
- compiled helper: arm64, SHA-256 `1f83577c9ca1e261b833991c650a3ad7db11cef189ab51146b6251456b22cfb5`. Xcode compilation took 2.5481 seconds once, before the timed samples. Subsequent profile commands reused this exact binary. The sample timer includes helper launch, PNG decode, encoding, GIF validation, and cleanup; it excludes compilation and fixture generation.
- `gifski`, `magick`, and `gifsicle` were absent. This run compares only the app's native ImageIO implementation and does not choose a release encoder or satisfy the visual-quality floor.

## fixtures and exact commands

fixtures used seed 7, 640×360, 240 frames, 24 fps, and 10 seconds. their manifest SHA-256 / combined frame-content SHA-256 values were:

| profile | manifest SHA-256 | frames SHA-256 |
| --- | --- | --- |
| mixed | `cd2a9ffb73a5908e221ae2fd0e28233b7a1ce426dee9f9b4239371c35b9c07e2` | `a2e07a4980e7b437bc1e44d6a9d8ff7f11c70126abaeeb9ad3a580ecd1143c9d` |
| mostly-static-ui | `6e2f785f8c29a9ca43cd1bbf91dd636e0405822c01438cb8a27ef1a7a35a28fa` | `d42ed02d552de0db283b9a2d720ac782b7b62dc8dd7c41817da0837b3ce71fc2` |
| fast-scrolling | `d31d28bcba4880b86dac358e81a87e466fe74631414db7e69528405338dc8eec` | `e0750bce46287c335993b3e2610505b0debe4f18fe7cfa25e700ff1cac850885` |
| high-motion-gradient-cursor | `8a90e5f8d09fe44045642bc1fb744d3865494ad8ede21e36b95ab06759f71c64` | `8436939cbc8b536dcc3ea3423669f4f0ccdda1dc14a75a3e5eee4b652b4c0c01` |

run from the repository root. the first command compiled the wrapper; following commands used the same binary:

```sh
python3 Benchmarks/run_encoder_benchmark.py --fixture Benchmarks/generated/mixed-640x360 --output Benchmarks/outputs/imageio-app-mixed-20261024 --runs 7 --candidates imageio-app
python3 Benchmarks/run_encoder_benchmark.py --fixture Benchmarks/generated/mostly-static-ui-640x360 --output Benchmarks/outputs/imageio-app-mostly-static-ui-20261024 --runs 7 --candidates imageio-app --imageio-app-binary Benchmarks/outputs/imageio-app-mixed-20261024/tools/imageio_app_encode
python3 Benchmarks/run_encoder_benchmark.py --fixture Benchmarks/generated/fast-scrolling-640x360 --output Benchmarks/outputs/imageio-app-fast-scrolling-20261024 --runs 7 --candidates imageio-app --imageio-app-binary Benchmarks/outputs/imageio-app-mixed-20261024/tools/imageio_app_encode
python3 Benchmarks/run_encoder_benchmark.py --fixture Benchmarks/generated/high-motion-gradient-cursor-640x360 --output Benchmarks/outputs/imageio-app-high-motion-gradient-cursor-20261024 --runs 7 --candidates imageio-app --imageio-app-binary Benchmarks/outputs/imageio-app-mixed-20261024/tools/imageio_app_encode
```

the GIFs and raw reports remain ignored under `Benchmarks/outputs/` and are not committed. each output directory contains `raw.json`, `summary.json`, and the eight retained GIFs. memory evidence is limited: peak resident bytes was null in these runs; the sampled-workspace number equals the GIF size and is not process memory. the 20 ms workspace poll may miss short-lived files. the structural validator does not assess visual fidelity or playback across apps. the high-motion-gradient-cursor profile is the recommended first profile for the later visual-quality-floor review; static UI/text also needs separate legibility review.
