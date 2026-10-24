# encoder package license evidence — 2026-10-24

this is a source-based engineering evidence report for two benchmark paths, not legal advice, redistribution clearance, or an encoder selection. it records visible license and attribution requirements and the evidence still needed for the exact production artifacts. upstream and Homebrew metadata can change; pin all inputs for a release.

## Gifski 1.34.0

the pinned source is tag `1.34.0`, commit `1060eab4500a20f27e2fa3ab7e85473d0e921cbd`; the audit records the default-feature arm64 CLI build and archive/input checksums in [the build audit](gifski-1.34.0-build-audit-2026-10-24.md). the root package declares `AGPL-3.0-or-later`. its enabled locked graph has 47 third-party crates. the recorded dependency-license table is based on crate-manifest identifiers, so the exact shipped closure and each copyright/license text still need to be assembled and checked for the release build.

two specific notice gaps were found in that pinned graph:

| package | evidence and exact gap | follow-up required |
| --- | --- | --- |
| `gif-dispose` 5.0.1 | its pinned manifest declares `MIT OR Apache-2.0`, but neither the published crate archive nor pinned source tree contains a `LICENSE`, `COPYING`, or `NOTICE` file. the manifest author field names Kornel Lesiński but does not give an explicit copyright holder/year notice. | obtain the exact publisher-provided license text and copyright notice for the pinned source before assembling distribution notices; do not fill in the MIT placeholder from the author field. preserve the selected license text and applicable notices. |
| `imagequant` 4.4.1 / pngquant lineage | the crate includes `COPYRIGHT`, but the Gifski publisher's [license and historical notices page](https://gif.ski/license.html) includes additional Greg Roelofs terms and Stefan Schneider attribution absent from that packaged file; the page says the notices accompany copies/supporting documentation and binary redistribution. | retain the exact crate `COPYRIGHT` and resolve inclusion of the complete publisher-published notice text for the pinned build. the prior audit did not save a page capture or content hash. |

the remaining 45 active crates have a manifest-declared identifier and a license-like file-name presence recorded in the build audit, but that scan does not establish exact text completeness or copyright notices. release evidence must map each active crate to its exact archive checksum, license text, copyright/attribution notices, and any applicable obligations. keep FFmpeg/video features disabled unless they receive a separate exact-build review. do not infer the shipped graph from Gifski's mutable `main` branch or a prebuilt executable.

## Homebrew ImageMagick 7.1.2-34 Q16-HDRI arm64

the benchmark machine reports ImageMagick `7.1.2-34 Q16-HDRI aarch64`, source revision `c5d4ca8a0:20261014`, binary SHA-256 `324c185d0dead1cf7326e7f87743da28086dde0a00538b96d5cd320ed7543466`. the `magick` binary's recorded direct links include its own `MagickCore`/`MagickWand`, Homebrew `freetype`, `little-cms2`, and `libtool`'s `libltdl`, plus macOS `libxml2`, `libbz2`, `libz`, `libSystem`, and `libc++`. the output of `magick -version` reports built-in delegates `bzlib freetype heic jng jpeg lcms ltdl lzma png tiff webp xml zlib zstd`.

inspection of the installed GIF and common image coder modules found additional dynamic links that `otool -L magick` alone does not show: `heic.so` loads `libheif`; `jpeg.so` loads `jpeg-turbo`; `png.so` loads `libpng`, `jpeg-turbo`, and `xz`/`liblzma`; `tiff.so` loads `libtiff`, `jpeg-turbo`, `xz`/`liblzma`, and WebP; `webp.so` loads WebP. these modules also reference the Homebrew `MagickCore`, `freetype`, `little-cms2`, `libltdl` and macOS libraries above. Homebrew's exact 2026-10-23 formula declares the ImageMagick License and dependencies `freetype`, `jpeg-turbo`, `libheif`, `libpng`, `libtiff`, `libtool`, `little-cms2`, `webp`, and `xz`, with macOS-provided `bzip2` and `libxml2`. its build enables modules, HEIC, and WebP. the benchmark did not archive all module and transitive dependency binaries or their source/license texts.

ImageMagick's pinned release source contains both `LICENSE` and `NOTICE`; the tested Homebrew Cellar also contains both. local copies hashed as follows: `LICENSE` `131447ad0099069beaa32acf1700716eea294a5bdf936d8211d7026b1849e5d4`, `NOTICE` `a58570cb757bd9223bed229f74cd85c3117c622d23553766427b4e816e65e1e1`. the version-pinned `LICENSE` requires recipients to receive a copy, requires clear attribution to ImageMagick Studio LLC, and requires prominent notices in modified files. because this release includes a `NOTICE`, its applicable attribution notices need a readable copy in a distributed NOTICE file, source/documentation, or the normal third-party-notices display. the pinned NOTICE lists ImageMagick Studio LLC and E. I. du Pont de Nemours and Company, plus OpenSSH, Xfig, ezXML, GraphicsMagick, Magick++, Thatcher Ulrich, Gsview, libsquish, and Bootstrap notices. retain the original pinned text and check which notices apply to the exact shipped source/build; do not replace it with the summary in the moving web page.

the installed Homebrew `opt` links on the benchmark machine resolved to the versions below. license identifiers come from Homebrew's official formula metadata generated on 2026-10-23/24; they are a screening index, not a component-by-component review.

| installed package | observed version | Homebrew license identifier |
| --- | --- | --- |
| FreeType | 2.15.0 | `FTL` |
| `jpeg-turbo` | 3.2.0 | `IJG AND Zlib AND BSD-3-Clause` |
| `libheif` | 1.23.6 | `LGPL-3.0-or-later` |
| `libpng` | 1.6.59 | `libpng-2.0` |
| `libtiff` | 4.7.2 | `libtiff` |
| GNU `libtool` | 2.6.2 | `GPL-2.0-or-later` (formula metadata) |
| Little CMS | 2.19.1 | `MIT` |
| WebP | 1.6.0 | `BSD-3-Clause` |
| XZ | 5.8.4 | `0BSD AND GPL-2.0-or-later` |
| `x265` (`libheif` dependency) | 4.3 | `GPL-2.0-or-later` |
| `libde265` (`libheif` dependency) | 1.1.3 | `LGPL-3.0-or-later` |
| AOM (`libheif` dependency) | 3.15.2 | `BSD-2-Clause` |

the actual `libheif.1.dylib` dependency list confirms runtime links to `libx265`, `libde265`, `libaom`, and `libsharpyuv`. GNU's [libltdl documentation](https://www.gnu.org/software/libtool/manual/html_node/Using-libltdl.html) identifies a separate LGPL license with a special exception for that component, even though Homebrew labels the broader `libtool` formula GPL-2.0-or-later. verify the exact files and terms for the component actually linked. recursively inspect every linked codec dependency and every coder/codec module included in the app; XZ also has a dual-license identifier, so do not report it as a single license without checking the shipped components and notices.

### exact gaps before a distributable build

- Gifski: the publisher-specific `gif-dispose` copyright/license texts and additional pngquant notice text remain unresolved; the remaining active crate texts/notices have not all been content-reviewed.
- ImageMagick: no missing core `LICENSE` or `NOTICE` text was identified in the installed formula. no complete archive of this exact build's dynamic modules, full transitive dependencies, exact license files, or attribution texts was made. the versions and formula metadata below are current reference points, not proof of the exact files shipped.
- both paths: record final source/build provenance and hashes; assemble all active dependency license and attribution texts in the source and app; resolve any unclear component notice with its publisher and qualified review. for copyleft components, identify the exact source and build materials and recipient source-delivery method. avoid bundling unused delegates/modules where a purpose-built build can support the GIF workflow, then repeat the inventory against that exact build.
- notarized direct distribution: sign the exact nested executable and every bundled dynamic library/module with the release identity, verify signatures and hardened-runtime behavior, submit the exact app to Apple notarization, and test launch/capture/encoding on a clean supported Mac without Homebrew or developer tools. signing/notarization does not supply license text, notices, corresponding source, or other component obligations.

## primary sources

- Gifski [tag](https://github.com/ImageOptim/gifski/tree/1060eab4500a20f27e2fa3ab7e85473d0e921cbd), [manifest](https://github.com/ImageOptim/gifski/blob/1060eab4500a20f27e2fa3ab7e85473d0e921cbd/Cargo.toml), [lockfile](https://github.com/ImageOptim/gifski/blob/1060eab4500a20f27e2fa3ab7e85473d0e921cbd/Cargo.lock), and [license](https://github.com/ImageOptim/gifski/blob/1060eab4500a20f27e2fa3ab7e85473d0e921cbd/LICENSE).
- [`gif-dispose` 5.0.1 pinned manifest and source tree](https://github.com/kornelski/image-gif-dispose/tree/e50dcfbd38056d75184720e6c45daf23db16cecb); canonical [MIT](https://spdx.org/licenses/MIT.html) and [Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0.txt) texts; Gifski publisher [pngquant notices](https://gif.ski/license.html).
- ImageMagick [7.1.2-34 release](https://github.com/ImageMagick/ImageMagick/releases/tag/7.1.2-34), pinned [`LICENSE`](https://github.com/ImageMagick/ImageMagick/blob/7.1.2-34/LICENSE), and pinned [`NOTICE`](https://github.com/ImageMagick/ImageMagick/blob/7.1.2-34/NOTICE).
- Homebrew [ImageMagick formula at tap commit `d5bb02675bc731429a9cf98547f6d24ecd1d1fa1`](https://github.com/Homebrew/homebrew-core/blob/d5bb02675bc731429a9cf98547f6d24ecd1d1fa1/Formula/i/imagemagick.rb) and the official [formula API](https://formulae.brew.sh/api/formula/imagemagick.json).
- official Homebrew formula metadata for [FreeType](https://formulae.brew.sh/api/formula/freetype.json), [`jpeg-turbo`](https://formulae.brew.sh/api/formula/jpeg-turbo.json), [`libheif`](https://formulae.brew.sh/api/formula/libheif.json), [`libpng`](https://formulae.brew.sh/api/formula/libpng.json), [`libtiff`](https://formulae.brew.sh/api/formula/libtiff.json), [GNU libtool](https://formulae.brew.sh/api/formula/libtool.json), [Little CMS](https://formulae.brew.sh/api/formula/little-cms2.json), [WebP](https://formulae.brew.sh/api/formula/webp.json), and [XZ](https://formulae.brew.sh/api/formula/xz.json). check the matching upstream source archives and files before release.
- official Homebrew formula metadata for [`x265`](https://formulae.brew.sh/api/formula/x265.json), [`libde265`](https://formulae.brew.sh/api/formula/libde265.json), and [`aom`](https://formulae.brew.sh/api/formula/aom.json), plus GNU's [libltdl license note](https://www.gnu.org/software/libtool/manual/html_node/Using-libltdl.html).
- Apple [distribution signing](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/) and [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) guidance.
