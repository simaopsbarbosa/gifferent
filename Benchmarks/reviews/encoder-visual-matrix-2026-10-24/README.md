# four-profile encoder visual review · 2026-10-24

## scope

this review sheet expands the previous two-profile sample set to all four synthetic profiles and four requested paths: Gifski 1.34.0, ImageMagick optimized at 35% diffusion, ImageMagick unoptimized at 35% diffusion, and the app ImageIO path. it reuses the cold outputs from the full matrix; no encoder was rerun. this is visual evidence collection, not encoder selection.

all outputs use the same 640 × 360, 240-frame, 24 fps, seed-7 fixture per profile. four coalesced decoded frames are included at indices 60, 120, 180, and 239 (2.500 s, 5.000 s, 7.500 s, and 9.958 s). the view uses 640 × 360 PNG snapshots; the page can enlarge them to 2×. the exact GIF outputs are identified by SHA-256 below.

## inspection notes

the sampled snapshots retained readable fixture text at native 640 × 360 size. cursor edges are visible in the high-motion-gradient-cursor samples. no distracting spatial gradient banding is apparent in the four sampled high-motion frames. these are visual spot-check observations only. because this sheet uses still images, it cannot determine whether gradients flicker during playback, nor does it establish the quality of unsampled frames. a full animated review across all profiles remains necessary to confirm the entire approved floor.

the four encoding paths do not use equivalent controls: Gifski used quality 90; both ImageMagick paths used Floyd–Steinberg diffusion at 35%, with `-layers Optimize` present only on the optimized path; the app path uses the existing `OriginalGIFEncoder` through system ImageIO. the review does not score, rank, or select an encoder.

## provenance

the GIF SHA-256 values and byte counts below were checked against the cold-run records in the committed full-matrix JSON summaries before frame extraction. fixture manifest and frame-set hashes identify the shared inputs. frame extraction used ImageMagick `-coalesce` before selecting each frame so delta-encoded GIF frames are rendered against their preceding disposal state.

| profile | fixture manifest SHA-256 | fixture frames SHA-256 |
| --- | --- | --- |
| mostly-static-ui | `6e2f785f8c29a9ca43cd1bbf91dd636e0405822c01438cb8a27ef1a7a35a28fa` | `d42ed02d552de0db283b9a2d720ac782b7b62dc8dd7c41817da0837b3ce71fc2` |
| mixed | `cd2a9ffb73a5908e221ae2fd0e28233b7a1ce426dee9f9b4239371c35b9c07e2` | `a2e07a4980e7b437bc1e44d6a9d8ff7f11c70126abaeeb9ad3a580ecd1143c9d` |
| fast-scrolling | `d31d28bcba4880b86dac358e81a87e466fe74631414db7e69528405338dc8eec` | `e0750bce46287c335993b3e2610505b0debe4f18fe7cfa25e700ff1cac850885` |
| high-motion-gradient-cursor | `8a90e5f8d09fe44045642bc1fb744d3865494ad8ede21e36b95ab06759f71c64` | `8436939cbc8b536dcc3ea3423669f4f0ccdda1dc14a75a3e5eee4b652b4c0c01` |

| profile | candidate | output bytes | output GIF SHA-256 |
| --- | --- | ---: | --- |
| mostly-static-ui | Gifski 1.34.0 | 15,311 | `3beeaabc6e18589bbb6c5b00cc5e1794a66a4d4ca7a65db2e9596a609064a555` |
| mostly-static-ui | ImageMagick optimized · 35% diffusion | 30,017 | `c05c2c3d5c1e0c2e9762d976722bf74bb1fe4df3cf4637fdb01764f9c517f67a` |
| mostly-static-ui | ImageMagick unoptimized · 35% diffusion | 1,343,849 | `e083afbd0532955093640578072febff49386293869e34b0e214574d16d54ae4` |
| mostly-static-ui | app ImageIO path | 11,815 | `79cbf85089cb8b64530472b91b715dd51e90690b00203935a0a07777ef3f4970` |
| mixed | Gifski 1.34.0 | 1,745,722 | `dfaa0b7866643a993cdea6ad1a5d5d91e760a3a1bef1cd07f04466b07ced35b9` |
| mixed | ImageMagick optimized · 35% diffusion | 4,079,548 | `5486f3022b37c4ae9abfe9049d7d672da72a9e5c3b4d51f935e4b86ff509fe83` |
| mixed | ImageMagick unoptimized · 35% diffusion | 4,360,444 | `de225acfddeee20ed3f61b034e7aa9ee5daf52efb4fcfcf8ae624b38a21929a3` |
| mixed | app ImageIO path | 2,595,223 | `37aa47e79bf02f91f83bf0bc92974b14ce745fc5636e24f1aa32ccd653abd36f` |
| fast-scrolling | Gifski 1.34.0 | 909,046 | `597db1b092d1351c1b482160fefb36a85a128bc3aca4808feb7e8cd7bb1871a9` |
| fast-scrolling | ImageMagick optimized · 35% diffusion | 1,207,910 | `408dbb59da42606c4354e34d2fcc17f5ca4c9d0463b96db412e48fbbe7a7bcda` |
| fast-scrolling | ImageMagick unoptimized · 35% diffusion | 1,672,572 | `ce211aeba8b4892f1cc6c30afe04bcaba7ff72862c554ffd3819bf7948715062` |
| fast-scrolling | app ImageIO path | 874,638 | `4194a5f956c9817af2bfa35a021aa346e20a70a713178752aa041f38c71476d8` |
| high-motion-gradient-cursor | Gifski 1.34.0 | 5,792,443 | `f4afa4f9e61d7b094cf6037f997c1a268b81fd85457a035a35032175f91efa1a` |
| high-motion-gradient-cursor | ImageMagick optimized · 35% diffusion | 9,524,098 | `e69ea343db4da5f0eda75b4aef35db7dd91edf8347ad128433b1eace8a288830` |
| high-motion-gradient-cursor | ImageMagick unoptimized · 35% diffusion | 12,263,510 | `2665d4e3b43b817f6458b42076f7f147feb554d19e0005cc90f2e857330b2a4f` |
| high-motion-gradient-cursor | app ImageIO path | 11,174,716 | `48ed3ac05798146230ddfb80964d504819afdb0f3fb705f017fae88f3d642784` |

the four compact full-matrix summaries are under [`Benchmarks/results/gifski-magick-35-full-matrix-2026-10-24`](../../results/gifski-magick-35-full-matrix-2026-10-24/). timing, output-size, and environmental limitations remain in the [full benchmark report](../../gifski-magick-35-full-matrix-2026-10-24.md).

## limitations

- snapshots cover only four of 240 frames per output. they support spatial inspection but not temporal flicker or complete playback review.
- the 2× view is browser enlargement of decoded 640 × 360 PNGs; it is not a second encoded output or a separate quality run.
- compression controls differ between candidate paths, so this does not isolate the effect of a single encoder variable.
- the fixture uses synthetic content and does not represent every macOS app, display, cursor, font, or real screen recording.
- no comparative score, release qualification, license clearance, or encoder choice is made here.

## source files

cold outputs were reused from the benchmark directories listed in the [full-matrix report](../../gifski-magick-35-full-matrix-2026-10-24.md). each path had the same output hash across the recorded cold and warm runs. fixture generators and run commands are documented in that report.
