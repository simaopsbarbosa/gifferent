# equal-work encoder visual spot check — 2026-10-24

open [`index.html`](index.html) locally for side-by-side source and decoded GIF frames at native size. expand each frame's `2× views` section for a nearest-neighbor enlargement. the page uses selected frames 0, 120, and 239 from the mostly-static UI and high-motion gradient/cursor fixtures.

## source and extraction

- source PNGs came from the existing seed 7, 640×360, 240-frame, 24-fps fixtures under `/Users/simaob/dev/gifferent/Benchmarks/generated/`.
- GIF samples came from each path's retained first-invocation GIF under the matching `equalized-static-ui-20261024` and `equalized-high-motion-20261024-rerun` directories in `/Users/simaob/dev/gifferent/Benchmarks/outputs/`.
- GIF frames were coalesced to the logical canvas before selecting each matched index; this avoids displaying optimized partial-frame rectangles as though they were full frames. each saved review PNG is a 640×360 RGB export with metadata stripped and PNG compression enabled. the HTML renders the same raster at 640×360 and 1280×720 using nearest-neighbor scaling.
- benchmark outputs used ImageMagick 7.1.2-34 Q16-HDRI arm64. the optimized ImageMagick path used `-layers Optimize`; the unoptimized path omitted that flag. both used Floyd–Steinberg, 100% diffusion, 256 colors, infinite looping, and the same frame-delay schedule. the ImageIO row is the legacy ImageIO helper. this is a representative visual sample; it does not reproduce the full dither-slider sweep.

## observation

the selected frames show legible text at native size and clear cursor edges. the high-motion samples preserve the broad gradient transitions without an obvious still-frame banding defect in these frames. the optimized ImageMagick 100% diffusion sample has visible speckling in flat dark UI regions at native size, more apparent at 2×; the ImageIO and unoptimized ImageMagick samples look cleaner in those regions. this is a concrete visual difference, not by itself a confirmed floor failure: the approved floor allows minor differences visible only at 2×, while this speckle is also faintly visible at native size. architect review is needed to classify whether its native-size visibility is distracting. no objective text-blur or cursor-edge loss was evident in these selected frames.

the architect reviewed the 100% diffusion sample and confirmed that the approved quality floor holds despite faint native-size speckling. this spot check cannot assess flicker, temporal noise, cursor trails over time, playback differences among applications, or other slider values. it does not select a release encoder. the benchmark also had no peak-resident-memory or CPU measurements, and this page makes no memory claim.

## provenance

| profile | source manifest sha-256 | combined source frames sha-256 | ImageIO GIF sha-256 | optimized ImageMagick GIF sha-256 | unoptimized ImageMagick GIF sha-256 |
| --- | --- | --- | --- | --- | --- |
| mostly-static-ui | `6e2f785f8c29a9ca43cd1bbf91dd636e0405822c01438cb8a27ef1a7a35a28fa` | `d42ed02d552de0db283b9a2d720ac782b7b62dc8dd7c41817da0837b3ce71fc2` | `79cbf85089cb8b64530472b91b715dd51e90690b00203935a0a07777ef3f4970` | `04486d8e9bed37a41e7c5427b40edc7187bb55fbfd63e50c0926a50c8dbe4f3f` | `827fa40e6eb707f4da991e3a94c52ae0516d390acc807b3cd74ef8691c2eee8d` |
| high-motion-gradient-cursor | `8a90e5f8d09fe44045642bc1fb744d3865494ad8ede21e36b95ab06759f71c64` | `8436939cbc8b536dcc3ea3423669f4f0ccdda1dc14a75a3e5eee4b652b4c0c01` | `48ed3ac05798146230ddfb80964d504819afdb0f3fb705f017fae88f3d642784` | `920469b091028088a456aaa67b6160f2a5bc16f529452455eb9c341756dcd321` | `a516ee69d64c432c319b1abe59a163fc1574b5fceda42c1bd6e410495eabf5be` |

benchmark host caveat: the reference environment was an arm64 MacBook Air M2 with 8 GB on macOS 27.0.1 build 26A434, Xcode 27.1 build 27A9275, AC power, and Low Power Mode off. sandboxed probes could not read the model, chip, or memory, and thermal telemetry was unavailable.
