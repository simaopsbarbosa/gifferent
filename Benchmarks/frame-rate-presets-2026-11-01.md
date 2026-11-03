# output FPS presets benchmark

date: 2026-11-01. machine: Mac14,2 (Apple M2 MacBook Air, 8 GB), macOS 27.0.1 / 26A434, Xcode 27.1 / 27A9275. battery power; low power mode off. exact start battery and power configuration are retained in the raw JSON.

## method

[the harness](compare_frame_rates.py) builds [the helper](frame_rate_encode.swift) with `swiftc -O` against the app's real edit model and ImageIO original encoder. two deterministic 640 by 360 master PNG timelines use the existing fixture renderer with seed 7: mostly static UI and high-motion gradient/cursor. each master has 1,800 frames interpreted at 60 fps. the 24 fps baseline selects source index `floor(index * 60 / 24)` from the same timeline, matching motion/time rather than comparing differently paced scenes. both paths retain an explicit terminal interval.

the legacy path encodes 24 captured frames per second without the new transform. the new path applies the actual edit transform to 60 captured frames per second and exports 50 fps at 1×. each profile/duration/path has one cold invocation followed by seven warm invocations. candidate order reverses on alternate rounds. p90 is nearest rank (the largest of seven warm runs). timings are indicative, not guarantees; this is one battery-powered reference Mac.

measurements include process launch, sequence transform, ImageIO GIF encoding, output metadata validation, and reading captured PNG sizes. `/usr/bin/time -l` supplies peak process RSS. they exclude screen capture, PNG creation/transport, main-app UI and publication, and complete stop-to-preview latency. captured PNG bytes measure retained fixture input, not maximum combined session reservations. the existing 512 mib app quota and 128 mib Gifski cache budget remain unchanged.

an initial exploratory run overlapped builds/native inspection and used a fixed path order. its results were superseded by the controlled repeat below, run after builds and the fixture app had stopped. the raw final report records fixture hashes, source hashes, per-sample output hashes, times, RSS, dimensions, counts, duration, and bytes. the helper always supplies terminal duration, so the later single-frame fallback change from 1/24 to 1/60 does not affect these fixtures.

## results

| fixture | duration | capture / export FPS | warm median / p90 seconds | median / p90 peak RSS, MiB | GIF bytes | captured PNG bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| mostly-static-ui | 10 s | 24 / 24 | 0.708 / 0.748 | 628.1 / 628.2 | 13,873 | 681,099 |
| mostly-static-ui | 10 s | 60 / 50 | 1.522 / 1.560 | 904.5 / 1012.8 | 20,661 | 1,702,864 |
| mostly-static-ui | 30 s | 24 / 24 | 2.239 / 2.495 | 1120.4 / 1205.9 | 33,209 | 2,043,267 |
| mostly-static-ui | 30 s | 60 / 50 | 5.502 / 5.793 | 1145.2 / 1279.4 | 53,563 | 5,108,554 |
| high-motion-gradient-cursor | 10 s | 24 / 24 | 1.067 / 1.082 | 660.1 / 660.2 | 11,175,152 | 2,078,371 |
| high-motion-gradient-cursor | 10 s | 60 / 50 | 2.276 / 2.308 | 1016.0 / 1078.5 | 23,274,722 | 5,196,078 |
| high-motion-gradient-cursor | 30 s | 24 / 24 | 3.237 / 3.584 | 1290.2 / 1504.6 | 33,516,453 | 6,235,544 |
| high-motion-gradient-cursor | 30 s | 60 / 50 | 7.983 / 8.406 | 1573.7 / 1639.2 | 69,816,860 | 15,588,052 |

all samples have the expected dimensions, infinite-loop metadata, frame counts, and exact 10/30 second duration. the 50 fps samples have only delays of at least 20 ms. all eight output hashes match within each path/profile/duration, confirming repeatable encoded content; identical content across different sampling rates is not expected.

## implications and remaining acceptance

50 fps exports encode more source moments and cost more time, memory, and bytes. these measurements do not establish the existing under-two-second stop-to-preview target at the new default. live sustained 60 fps throughput, PNG pipeline cost, dropped frames, CPU, whole-app memory, and complete preview latency still need real-Mac acceptance. the architect accepted the measured encoding tradeoff and retained the 50 fps default on 2026-11-01; see [the recorded decision](../decisions.md). this does not waive live capture or full-preview acceptance. animated visual quality still requires architect review.

the existing ImageIO encoder remains the original-GIF path; this feature does not select a new encoder or alter its palette settings. a per-frame autorelease-pool experiment did not establish a reliable improvement in retained encoder memory and was not included. required quality review still includes fine text, cursor edges, banding, and temporal flicker at native size; frame ordering and metadata tests alone do not prove that floor.

raw final measurements: [results JSON](results/frame-rate-presets-2026-11-01.json). generated fixture PNGs and representative GIFs remain local under `/private/tmp/gifferent-fps-benchmark-2026-11-01-controlled`; they contain synthetic content only and are intentionally outside Git.

## reproduction

use a fresh output directory; generating both full master timelines and running 64 encoder invocations takes several minutes:

```sh
python3 Benchmarks/compare_frame_rates.py --output /private/tmp/gifferent-fps-review --runs 7
```

for a controlled repeat using an existing complete master fixture set:

```sh
python3 Benchmarks/compare_frame_rates.py --output /private/tmp/gifferent-fps-repeat --fixture-root /private/tmp/gifferent-fps-review --runs 7
```

keep other builds and apps idle during measured samples. the first successful warm GIF for each path/profile/duration is retained in the output directory for visual review. a fresh run also retains the master PNG directories; a repeated run uses the specified fixture root.
