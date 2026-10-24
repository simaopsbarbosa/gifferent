# gif encoder visual review samples

these are representative cold-run outputs from the synthetic benchmark. the four looping gifs are 640×360 and displayed at their native size. compare each pair at 1× playback.

## review request

please judge whether each candidate meets the approved quality floor:

- text remains legible at native size.
- cursor edges stay clear.
- gradients show no distracting banding or flicker.
- differences visible only at 2× are acceptable.

the controls are not equivalent: Gifski used quality 90; ImageMagick used 35% Floyd–Steinberg diffusion. these samples support visual inspection only. they are not a quality score, a final release test, or an encoder selection.

open [the review page](index.html) in a browser for side-by-side looping playback. the complete timing/size results and limits are in the [benchmark report](../../gifski-magick-35-2026-10-24.md); build and license evidence is in the [Gifski audit](../../gifski-1.34.0-build-audit-2026-10-24.md).

## sample provenance

both profiles use the same 640×360, 240-frame, 24 fps fixture per candidate, generated with seed 7. the gifs below are the retained cold-run outputs; all runs for a given candidate/profile had the same output checksum.

| profile | candidate | bytes | sample SHA-256 | fixture manifest SHA-256 |
| --- | --- | ---: | --- | --- |
| mostly-static-ui | Gifski 1.34.0 | 15,311 | `3beeaabc6e18589bbb6c5b00cc5e1794a66a4d4ca7a65db2e9596a609064a555` | `6e2f785f8c29a9ca43cd1bbf91dd636e0405822c01438cb8a27ef1a7a35a28fa` |
| mostly-static-ui | ImageMagick 7.1.2-34, optimized, 35% diffusion | 30,017 | `c05c2c3d5c1e0c2e9762d976722bf74bb1fe4df3cf4637fdb01764f9c517f67a` | `6e2f785f8c29a9ca43cd1bbf91dd636e0405822c01438cb8a27ef1a7a35a28fa` |
| high-motion-gradient-cursor | Gifski 1.34.0 | 5,792,443 | `f4afa4f9e61d7b094cf6037f997c1a268b81fd85457a035a35032175f91efa1a` | `8a90e5f8d09fe44045642bc1fb744d3865494ad8ede21e36b95ab06759f71c64` |
| high-motion-gradient-cursor | ImageMagick 7.1.2-34, optimized, 35% diffusion | 9,524,098 | `e69ea343db4da5f0eda75b4aef35db7dd91edf8347ad128433b1eace8a288830` | `8a90e5f8d09fe44045642bc1fb744d3865494ad8ede21e36b95ab06759f71c64` |
