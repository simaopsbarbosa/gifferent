# encoder candidate research

research snapshot: 2026-10-22. this note does not select a tool or establish legal compatibility. pin a release or commit and repeat the checks against the exact binaries before packaging.

## candidates and distribution questions

| candidate | upstream evidence | open review |
| --- | --- | --- |
| `gifski` CLI | [`Cargo.toml`](https://github.com/ImageOptim/gifski/blob/main/Cargo.toml) declares `AGPL-3.0-or-later`. the [README](https://github.com/ImageOptim/gifski/blob/main/README.md) accepts PNG frames and says video decoding through FFmpeg is optional. the default CLI features include an internal `gifsicle` feature implemented in [`src/gifsicle.rs`](https://github.com/ImageOptim/gifski/blob/main/src/gifsicle.rs). | inspect the pinned source and dependency tree, including the provenance and obligations of the internal feature. the [publisher's notice page](https://gif.ski/license.html) identifies inherited `libimagequant`/pngquant notices that must be carried into distribution. do not enable optional FFmpeg support without a separate dependency and license review. |
| `gifsicle` CLI | the upstream [README license section](https://github.com/kohler/gifsicle/blob/master/README.md#license) says GPL version 2 only and describes a separate alternative license with custom terms. the [README](https://github.com/kohler/gifsicle/blob/master/README.md) describes GIF manipulation and optimization. | review the exact license path and binary source obligations. do not treat its custom alternative as automatic permission for this app. `gifsicle` operates on an existing GIF, so benchmark the entire path that creates that GIF first. |

[GNU's license list](https://www.gnu.org/licenses/license-list.html#AGPLv3.0) says AGPLv3 and GPLv2 are incompatible when their code is combined. [GNU's aggregation guidance](https://www.gnu.org/licenses/gpl-faq.en.html#MereAggregation) says command-line arguments, pipes, and files normally connect separate programs, while the semantics of communication also matter. a separately executed, bundled `gifsicle` may be a distinct work, but that determination needs review of the actual integration and distribution layout. no `gifsicle` code should be linked or copied into the app on the strength of this note.

for any shipped executable, record the pinned upstream revision and binary checksum, architecture slices, build flags, all transitive licenses and required notices, corresponding source and build instructions, and the app bundle path. verify that source access accompanies the binary distribution and that the nested executable can be signed and notarized. [GNU's source distribution guidance](https://www.gnu.org/licenses/gpl-faq.en.html#UnchangedJustBinary) applies even to unmodified redistributed binaries.

## reproducible comparison

1. generate deterministic, non-sensitive 10-second PNG sequences at 24 fps. include high-contrast small text with cursor motion, moving flat-color UI shapes, and high-motion photographic/color gradients. use one fixed generator seed, color profile, dimensions, frame names, and timestamps. add a second resolution only after the first comparison works.
2. measure complete paths from identical frames and timing: **a**, PNG sequence → `gifski` → GIF; **b**, PNG sequence → an ImageIO GIF baseline → `gifsicle` → GIF. record ImageIO creation time in path **b**. a `gifsicle`-only timing is useful as a component measurement, not an end-to-end comparison.
3. capture exact build revisions, checksums, CLI help/version output, command arguments, ImageIO settings, machine model, chip, memory, macOS version, power mode, and thermal state. run an initial cold sample and repeated warm samples on the same machine. preserve raw per-run values and report the median and a tail statistic with its sample count.
4. for each path, record elapsed time, time to first usable preview, peak resident memory, CPU use, peak temporary disk, output bytes, dimensions, decoded frame count, frame delays, and loop behavior. inspect the GIF at 1× and 2× for text readability, gradients, motion smearing, flicker, and dither noise. compare equivalent quality settings through observed output rather than treating different tools' quality numbers as equivalent.
5. separately test processing during recording versus after stop using the same source frames. include process launch, frame staging, cancellation, and cleanup costs in the user-visible latency. retain small visual samples and the exact commands with each result.

the [latency goals](../vision.md) and [quality floor](../decisions.md) are unresolved measurements and product gates. present speed, memory, output size, and visual tradeoffs before choosing a CLI or packaging binaries.
