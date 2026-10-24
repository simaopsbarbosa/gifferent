# encoder license and distribution audit

research date: 2026-10-24. this is a source-based engineering screen, not legal advice, a final dependency review, or an encoder selection. it checks plausible distribution of each candidate inside the public, direct-download macOS app whose repository license is AGPL-3.0-or-later. review the exact source, build, and binary that would ship before closing the release gate.

upstream versions visible when checked: gifski 1.35.0 in its mutable `main` manifest; Gifsicle 1.96 in upstream release notes; ImageMagick 7.1.2-34 in its official release list. these are provenance observations only, not a recommendation to use those versions. before a build, resolve the intended release/tag to a full commit hash and archive source checksums and build inputs.

## summary

| candidate | plausible in an AGPL-3.0-or-later direct download? | main distribution conditions and open risk |
| --- | --- | --- |
| native ImageIO | yes, lowest third-party licensing burden | use the public macOS Image I/O framework supplied by the operating system; no separate encoder executable or ImageIO source bundle is being redistributed. keep using the Apple SDK/platform distribution path and validate the actual GIF output independently. |
| `gifski` CLI | yes, subject to source and dependency compliance | upstream declares AGPL-3.0-or-later, which matches the app's selected license family. convey the applicable full license and notices, make the corresponding source for the shipped build available under the AGPL terms, identify modifications, and audit all locked crates and enabled features. include the upstream `pngquant` historical notices. |
| ImageMagick `magick` CLI | yes, subject to a build-specific dependency audit | the ImageMagick License expressly permits redistribution and different-license combinations and says it is GPLv3-compatible. include its full license and clear attribution; mark modified ImageMagick files. audit every enabled coder, delegate, linked library, and bundled configuration for its own terms. |
| Gifsicle CLI | unresolved; do not treat as cleared for bundling | upstream's primary terms are GPL-2.0-only. the upstream alternative license requires contacting the author for permission when the source-code context would violate GPL terms. separate executable plus simple file/argument exchange is evidence for separation, but whether inclusion in this app bundle is an aggregate or one combined distribution is a legal question. obtain qualified review or written permission before packaging it. |

the ranking above concerns distribution burden only. it does not rank output quality, performance, feature fit, or engineering readiness. no candidate is selected by this note.

independent app-wide AGPL gate: regardless of encoder, verify the recipient source-delivery method against AGPLv3 section 6 for each covered binary, preserve license/copyright/warranty notices, and provide the appropriate legal notices for the interactive app interface under section 5(d). the repository's `LICENSE` is necessary but does not by itself prove that a shipped binary's complete corresponding source and notices are available.

## candidate findings

### native ImageIO

the implemented candidate calls `CGImageDestination` from Apple's Image I/O framework. Apple's documentation describes it as the system API for writing image data to a URL, data object, or data consumer, including multi-image output; the API reference also documents GIF frame delay and loop metadata. this route adds no separately bundled third-party encoder executable. the framework is provided by macOS rather than copied into the app, so there is no ImageIO source-offer or third-party notice obligation identified for this candidate. use the public SDK and normal Apple signing/notarization requirements for the app. the API documentation is evidence of API capability, not a substitute for checking the applicable Apple developer and platform terms.

remaining gate: the current candidate remains a test seam. verify GIF timing, loop, color, alpha, dimensions, frame count, cancellation, memory, quality, and performance on the pinned supported systems. this legal screen does not answer those technical questions.

### `gifski`

the current upstream manifest identifies version 1.35.0 and declares `AGPL-3.0-or-later`; the repository contains the corresponding AGPL license. its manifest currently lists `imagequant` 4.4.1, whose upstream states GPL-3.0-or-later for open-source use. AGPLv3 section 13 expressly permits combining an AGPL-covered work with a GPLv3-covered work into one combined work, while each part remains under its stated license. this makes the visible top-level license combination plausible for this AGPL app, subject to a complete audit of the exact locked dependency graph.

for a distributed binary, retain and publish the complete corresponding source and scripts needed to build, install, and run the shipped version in a form permitted by AGPLv3 section 6; include the AGPL text and preserve copyright, license, and warranty notices. if modified, clearly identify the modifications and relevant dates. because the app itself is AGPL-3.0-or-later, assess the app and CLI as distributed together under the actual integration before deciding whether they form one covered work; do not rely on the CLI boundary to avoid source obligations. the project already plans to ship source and notices, but the release must point recipients to the exact matching source revision and build materials.

the gifski publisher separately publishes historical `pngquant` notices and asks that they be reproduced in documentation/supporting materials. include those notices if present in the pinned build. audit all exact locked crates, their licenses and copyright notices, generated code, compiler/runtime components, and enabled features. keep optional video/FFmpeg support disabled unless separately reviewed; gifski's upstream notes that it brings FFmpeg licensing and possible codec patent questions. do not infer the shipped dependency/license set from the mutable `main` manifest or a prebuilt download.

### ImageMagick `magick`

ImageMagick's official license permits use in packages and distributions, linking with different licenses, and merging code into a differently licensed work. it identifies compatibility with GPLv3. the GNU license guidance recognizes AGPLv3/GPLv3 combinations; on the published terms, ImageMagick is a plausible candidate for this AGPL app.

for redistribution, include the full ImageMagick License and clear attribution to ImageMagick Studio LLC. retain relevant copyright, patent, trademark, and attribution notices in source; put readable attributions in a `NOTICE` file or documentation when present. prominently mark any modified ImageMagick files. ImageMagick's license does not itself require publishing ImageMagick source or modifications, but other bundled components can impose separate source and notice requirements.

do not use a developer's Homebrew install as distribution evidence. the official download page says the macOS package-manager build includes delegate libraries, and documents a wider `imagemagick-full` dependency set. for the selected exact source build, record enabled coders/delegates, configure options, configuration/policy files, dynamic libraries, architectures, checksums, and each dependency's license. exclude unnecessary delegates and impose a restrictive runtime policy. a tool's license alone does not clear its compiled bundle.

### Gifsicle

the upstream README says the code is distributed under GNU GPL version 2 only, and also offers alternative terms. that alternative permits copying/modifying with source notices retained, but requires obtaining the author's permission for use in a product/source context that would violate GPL terms. it is not blanket approval for this app.

GNU's own FAQ says separate programs may be distributed as an aggregate even when licenses are incompatible, and explains that command-line arguments and files are ordinary separate-program communication; it also says the line between an aggregate and a combined program is a legal question that depends on substance and form. Gifferent would invoke Gifsicle as a nested executable and pass a GIF path, which supports separation, but the executable would be shipped inside the app's direct-download bundle as part of the GIF workflow. this research cannot conclude whether that packaging and relationship is a mere aggregate. the GPL-2-only and AGPLv3 terms cannot both govern one combined work under the stated terms.

release options: obtain a written commercial/alternative license that covers this exact distribution; have qualified counsel assess whether the actual bundle and invocation are separate programs; or omit Gifsicle from the shipped app. if separate distribution is approved under GPL-2.0, include the full GPLv2 text, preserve notices, and satisfy its exact corresponding-source delivery route for the exact binary and any modifications. do not assume gifferent's AGPL source link alone satisfies Gifsicle's separate GPLv2 obligations.

## provenance required before any bundled candidate

for the exact candidate chosen after the separate benchmark and quality gates, archive:

- upstream project URL, immutable version/tag, full commit hash, source archive checksum, and date acquired;
- build recipe and scripts, compiler/toolchain versions, target SDK and minimum OS, architecture(s), feature/configuration flags, and lockfiles;
- final executable SHA-256, `file`/`lipo` output, `--version` and help output, linked-library inventory, and a clean-Mac execution record;
- complete direct and transitive dependency inventory with exact versions, license identifiers and texts, copyright/attribution notices, exceptions, and any source or permission obligations;
- all required license texts and notices in both source repository and distributable; modified-file/source notices where terms require them; exact corresponding source and build materials for copyleft binaries;
- signature verification, nested-code signing record, notarization result, and clean supported-Mac launch with no package manager or developer tools installed.

This matches the existing repository release gate. Apple requires distribution signing before direct macOS distribution and notarization; signing and notarization do not replace open-source license obligations.

## official sources checked

accessed 2026-10-24. upstream manifests, repository branches, and release pages can change; pin and re-check the exact revision used for a release.

- [gifski `Cargo.toml`](https://github.com/ImageOptim/gifski/blob/main/Cargo.toml) — current package version, license, features, and dependency versions.
- [gifski `LICENSE`](https://github.com/ImageOptim/gifski/blob/main/LICENSE) and [gifski README](https://github.com/ImageOptim/gifski) — AGPL terms and optional FFmpeg note.
- [gifski publisher license and pngquant notices](https://gif.ski/license.html) — additional historical binary notices.
- [libimagequant upstream README](https://github.com/ImageOptim/libimagequant) — GPL-3.0-or-later open-source license and commercial-license statement.
- [GNU AGPLv3](https://www.gnu.org/licenses/agpl-3.0.html) — source/conveyance terms and section 13 compatibility with GPLv3.
- [ImageMagick license](https://imagemagick.org/license/) — redistribution, attribution, modified-file notices, and license compatibility statements.
- [ImageMagick official macOS download/dependency notes](https://imagemagick.org/script/download.php/) — package-manager delegate libraries and wider builds.
- [Gifsicle README and license](https://github.com/kohler/gifsicle) and [Gifsicle release history](https://github.com/kohler/gifsicle/blob/master/NEWS.md) — GPL-2-only, alternative permission terms, and current release history.
- [GNU FAQ on GPL compatibility and aggregation](https://www.gnu.org/licenses/gpl-faq.en.html#MereAggregation) — separate programs, mechanisms of communication, and unresolved legal boundary.
- [Apple Image I/O documentation](https://developer.apple.com/documentation/imageio) and [`CGImageDestination`](https://developer.apple.com/documentation/imageio/cgimagedestination) — system framework and image-output API.
- [Apple distribution signing guidance](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/) and [notarization guidance](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) — direct macOS distribution requirements.

