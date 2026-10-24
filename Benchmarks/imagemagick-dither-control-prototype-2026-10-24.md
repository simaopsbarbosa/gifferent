# imagemagick dither control prototype — 2026-10-24

## status

this bounded prototype checks the architect-approved 0–100% diffusion control against the already-installed Homebrew ImageMagick binary. it confirms that the option changes encoded pixels and output size on two sparse four-frame samples. it does not measure full-sequence animation quality, prove the approved quality floor, compare complete encoder paths, select a release candidate, or establish performance.

## setup

- executable: `/opt/homebrew/bin/magick`, ImageMagick 7.1.2-34 Q16-HDRI aarch64, upstream revision `c5d4ca8a0:20261014`.
- fixtures: existing `high-motion-gradient-cursor-640x360` and `mostly-static-ui-640x360` generated fixtures; no private screen content.
- source frames: indices 0000, 0060, 0120, and 0180 from each 240-frame sequence.
- settings held fixed: 640×360 input frames, `FloydSteinberg`, 256 colors, infinite loop, and `dither:diffusion-amount` at 0%, 35%, or 70%. the command's `-delay 10` applies to the four supplied images; this run did not validate the full 24 fps schedule.
- outputs were written to a new `/private/tmp/gifferent-dither-sweep.ohHkW9` directory. no packages were installed and no tracked or pre-existing benchmark outputs were changed.

the command for each setting was:

```sh
/opt/homebrew/bin/magick \
  -delay 10 "$fixture/frame_0000.png" "$fixture/frame_0060.png" \
  "$fixture/frame_0120.png" "$fixture/frame_0180.png" \
  -dither FloydSteinberg \
  -define "dither:diffusion-amount=${pct}%" \
  -colors 256 -loop 0 "$output"
```

## results

all six GIFs had four frames at 640×360. each setting produced a distinct SHA-256 for each fixture, and first-frame pixel comparisons were nonzero between every pair. times are single prototype invocations and are not comparable performance evidence.

| fixture | diffusion | bytes | elapsed | sha-256 |
| --- | ---: | ---: | ---: | --- |
| high-motion gradient/cursor | 0% | 195,873 | 0.133 s | `ac33ed5ce5bb83d20579ba82c28837e5179691f039d6a11edc915b9ace783178` |
| high-motion gradient/cursor | 35% | 203,649 | 0.117 s | `6c727ca1b30c49775a75887b635771050043cb9b3c7eb98fdfd4a1a179aba9a6` |
| high-motion gradient/cursor | 70% | 243,388 | 0.119 s | `7fb90b00e1e5912b0b327a96c50a187bc4e3cb0cfedc4afb295efe63ca431222` |
| mostly static UI | 0% | 16,848 | 0.093 s | `304d3853731c9d7bd6a2ef79e85a408f3b97a9a84f7701c9bb44af15d104d40d` |
| mostly static UI | 35% | 22,473 | 0.094 s | `dcbe2312378fac5070873cf20a04a8880f483e0d6e1cd3d00987fa95d89ff63c` |
| mostly static UI | 70% | 42,900 | 0.096 s | `c9fb0e5e956b0a2d6928fcbbd7855a979fb222349439ad4481357c6c9aafe084` |

ImageMagick `compare -metric AE` reported normalized first-frame differences for the high-motion fixture of 0.00177 (0↔35), 0.00112 (35↔70), and 0.00280 (0↔70); for mostly-static UI it reported 0.00651, 0.00256, and 0.00783 respectively. these values indicate changed pixels, not whether the changes improve or harm visual quality.

## conclusion and next evidence

the installed build accepts the documented option and the option has an observable output effect on both tested fixtures. encoded sizes increased with the setting in these samples; that does not establish a quality relationship or monotonic behavior across full sequences. a future quality pilot must encode full sequences, validate timing and looping, retain one representative output per setting, and review identical frames at native size and 2× for text, cursor edges, gradients, banding, flicker, and temporal artifacts. review remains against the architect-approved floor in [`decisions.md`](../decisions.md). the Homebrew build is exploratory only; release distribution and dependency audits remain open.
