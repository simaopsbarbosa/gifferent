# Gifski quality sweep · 2026-10-24

## evidence note

this focused sweep compares Gifski 1.34.0 qualities 70, 80, 90, and 100 on the existing mostly-static-ui and high-motion-gradient-cursor fixtures. each combination was encoded three times. all use the identical sorted 240 PNG frames, 640 × 360 dimensions, 24 fps, `--repeat 0`, and `--no-sort`; only `--quality` changes. the looping review page contains one retained full output per profile/quality. the other two run outputs were discarded after size, timing, metadata, and hashes were recorded.
the invocation shape was `gifski --fps 24 --quality <70|80|90|100> --repeat 0 --no-sort -o <output.gif> <frame_0000.png> … <frame_0239.png>`. quality 90 remains the baseline reference. the [existing animated quality-90 review](../gifski-magick-35-2026-10-24/index.html) is preserved and linked from the comparison page.

## results

wall times use `time.perf_counter()` around the Gifski process. median and nearest-rank p90 use three samples; p90 is the slowest of those three and should be treated as indicative. output size and SHA-256 were identical across all three runs for every setting. all outputs validated at 640 × 360, 240 frames, 10.0 seconds, and infinite looping.

| profile | quality | bytes | median wall time | p90 wall time | output SHA-256 |
| --- | ---: | ---: | ---: | ---: | --- |
| mostly-static-ui | 70 | 15,208 | 0.670 s | 0.675 s | `e32eca7890b860fff1b075c11b6ebdf264f133c39d1c739fcb19f364746ca873` |
| mostly-static-ui | 80 | 15,287 | 0.623 s | 0.661 s | `8684aa3378f00682fe0e68205218075227fb5822cf00ac88374ba86f9a3992f4` |
| mostly-static-ui | 90 | 15,311 | 0.603 s | 0.638 s | `3beeaabc6e18589bbb6c5b00cc5e1794a66a4d4ca7a65db2e9596a609064a555` |
| mostly-static-ui | 100 | 15,365 | 0.620 s | 0.629 s | `1e66ca32adeec8f7be22585397c8860dab96cfa3380e4ed2fb363f75658a5cb1` |
| high-motion-gradient-cursor | 70 | 3,519,840 | 1.260 s | 1.373 s | `849807d4413d6a39df655cae8bed869d220299026aa83b0d52c27f0d4998de00` |
| high-motion-gradient-cursor | 80 | 5,590,800 | 1.653 s | 2.413 s | `c91ea1af1ab109a2ef7b0802f9ecb6e007225248c73a44c0e5bbd0c732e06300` |
| high-motion-gradient-cursor | 90 | 5,792,443 | 1.388 s | 1.799 s | `f4afa4f9e61d7b094cf6037f997c1a268b81fd85457a035a35032175f91efa1a` |
| high-motion-gradient-cursor | 100 | 14,562,564 | 1.404 s | 2.607 s | `44ea456509fbadf41e287b5765f8361cde86d29a9a3896e089ddb167aa6ae175` |

## provenance and limits

- Gifski binary: 1.34.0; SHA-256 `f5f73e09fba870a21e8c502f3191e58633e5081b1914f71e32d5ee714450e839`.
- host: macOS 27.0.1, arm64. wall time is reported; CPU and resident memory were not measured in this focused sweep.
- mostly-static-ui fixture manifest SHA-256: `6e2f785f8c29a9ca43cd1bbf91dd636e0405822c01438cb8a27ef1a7a35a28fa`; frame-set SHA-256: `d42ed02d552de0db283b9a2d720ac782b7b62dc8dd7c41817da0837b3ce71fc2`.
- high-motion-gradient-cursor fixture manifest SHA-256: `8a90e5f8d09fe44045642bc1fb744d3865494ad8ede21e36b95ab06759f71c64`; frame-set SHA-256: `8436939cbc8b536dcc3ea3423669f4f0ccdda1dc14a75a3e5eee4b652b4c0c01`.
- quality 90 hashes match the earlier full-matrix outputs for both profiles, confirming the same inputs, binary, and flags.
- page controls pause/resume all loops and starts with still frames when `prefers-reduced-motion` is enabled.
- the page and note are evidence only. they make no quality-floor judgment, do not change product decisions, and do not claim architect approval or encoder selection.
