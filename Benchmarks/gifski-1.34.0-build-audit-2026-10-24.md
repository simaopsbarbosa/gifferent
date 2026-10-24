# gifski 1.34.0 source and build audit — 2026-10-24

## status

this is provenance research for a benchmark candidate, not an encoder selection or quality result. the official [release page](https://github.com/ImageOptim/gifski/releases) identifies 1.34.0 as latest. GitHub's official [`main` manifest](https://github.com/ImageOptim/gifski/blob/main/Cargo.toml) reports 1.35.0, but its [release/tag refs](https://github.com/ImageOptim/gifski/releases) do not publish a 1.35.0 release; direct `git ls-remote` below returned no 1.35.0 ref. the 1.35.0 manifest is an unreleased development snapshot and is not this audit's source. the pinned 1.34.0 build and focused 35% ImageMagick comparisons are recorded here and in the [comparison report](gifski-magick-35-2026-10-24.md).

the official tag `1.34.0` resolves to commit `1060eab4500a20f27e2fa3ab7e85473d0e921cbd`. i cloned that exact revision to `/private/tmp/gifferent-gifski-1.34.0-src`; no files were changed in the gifferent repository. a deterministic local `git archive` of that commit was made outside the checkout for hash evidence. the source and lockfile were inspected, and target-specific dependency metadata was resolved. the no-FFmpeg default-feature release build completed successfully after the integration owner cleared the shared host.

## pinned source and feature set

the tag's manifest reports `gifski` 1.34.0, edition 2021, minimum Rust 1.74, and `AGPL-3.0-or-later`. default features are `gifsicle` and `binary`, which provide the CLI. `video` enables optional `ffmpeg-next`; `video-static` and `video-prebuilt-static` build on that option. the upstream documented `cargo build --release` command with `--locked` is therefore the no-FFmpeg default CLI build. `gifsicle` is an internal Rust feature, not the separate Gifsicle executable.

the build target for the active dependency inventory is `aarch64-apple-darwin`. toolchain in the task's temporary homes: `cargo 1.85.0 (d73d2caf9 2024-12-31)` and `rustc 1.85.0 (4d91de4e4 2025-02-17)`. the build completed with `Finished release profile [optimized] target(s) in 16.75s`; full log: `/private/tmp/gifski-build-1.34.0.log`. target output is under `/private/tmp/gifski-target-1.34.0`. the executable SHA-256 is `947969d778a894e9b2c281bc96c6644ba88a16aba6e64b3cd2a4f5e219d8de46`; `file` reports `Mach-O 64-bit executable arm64`, `lipo -info` reports `arm64`, and `gifski --version` prints `gifski 1.34.0`. `otool -L` lists only `/usr/lib/libiconv.2.dylib` and `/usr/lib/libSystem.B.dylib`, with no FFmpeg linkage. complete `--help` output is `/private/tmp/gifski-1.34.0-help.txt`. this prototype binary is unsigned and not notarized.

| evidence | value |
| --- | --- |
| official tag ref | `refs/tags/1.34.0` |
| peeled source commit | `1060eab4500a20f27e2fa3ab7e85473d0e921cbd` |
| generated source archive | `/private/tmp/gifski-1.34.0-source-1060eab.tar.gz` |
| generated archive SHA-256 | `c50b04e9a9c1d548b20387c2ad5cec23948be5353c949aa6411afd63a85232cc` |
| `Cargo.toml` SHA-256 | `5738d2ed632ece91a87a129598c180b866b7133344c8bbe732dd13f18ef640ec` |
| `Cargo.lock` SHA-256 | `d407a44d19ad1527baccdc5a07477cdba2872dc60bb09f2c524503dd26a3ce2f` |
| upstream `LICENSE` SHA-256 | `4e2b565ed4c9537443eb92a10d745a6f8aeb75fa086fd7b955bb52e2cde48a4d` |

the source archive hash is for the locally generated `git archive` stream compressed with `gzip -n`; it is not an upstream release-asset checksum. the lockfile has 103 package entries across all optional and platform-specific dependencies.

## locked dependency and license inventory

`cargo metadata --locked --format-version 1` exited 0 and resolved 66 package metadata records. `cargo tree --locked --target aarch64-apple-darwin --edges normal,build --format '{p}'` exited 0 and listed the default-feature target graph with 47 active dependency packages plus the `gifski` root. the table records each active third-party crate version and the SPDX-like license expression declared in its package manifest. it is inventory evidence, not a legal clearance or review of each license's terms.

| declared license | count | active packages |
| --- | ---: | --- |
| `Apache-2.0 OR MIT` | 3 | `autocfg` 1.5.0, `utf8parse` 0.2.2, `wild` 2.2.1 |
| `BSD-2-Clause` | 1 | `yuv` 0.1.9 |
| `CC0-1.0 OR Apache-2.0` | 1 | `imgref` 1.11.0 |
| `CC0-1.0 OR MIT-0 OR Apache-2.0` | 1 | `dunce` 1.0.5 |
| `GPL-3.0-or-later` | 1 | `imagequant` 4.4.1 |
| `MIT` | 7 | `loop9` 0.1.5, `natord` 1.0.9, `pbr` 1.1.1, `resize` 0.8.8, `rgb` 0.8.51, `strsim` 0.11.1, `y4m` 0.8.0 |
| `MIT OR Apache-2.0` | 28 | `anstream` 0.6.19, `anstyle` 1.0.11, `anstyle-parse` 0.2.7, `anstyle-query` 1.1.3, `arrayvec` 0.7.6, `cfg-if` 1.0.1, `clap` 4.5.41, `clap_builder` 4.5.41, `clap_lex` 0.7.5, `colorchoice` 1.0.4, `crc32fast` 1.5.0, `crossbeam-channel` 0.5.15, `crossbeam-deque` 0.8.6, `crossbeam-epoch` 0.9.18, `crossbeam-utils` 0.8.21, `either` 1.15.0, `flate2` 1.1.2, `gif` 0.13.3, `gif-dispose` 5.0.1, `is_terminal_polyfill` 1.70.1, `libc` 0.2.174, `num-traits` 0.2.19, `once_cell` 1.21.3, `ordered-channel` 1.2.0, `rayon` 1.10.0, `rayon-core` 1.12.1, `thread_local` 1.1.9, `weezl` 0.1.10 |
| `MIT/Apache-2.0` | 1 | `quick-error` 2.0.1 |
| `Zlib` | 3 | `libz-rs-sys` 0.5.1, `lodepng` 3.12.1, `zlib-rs` 0.5.1 |
| `Zlib OR Apache-2.0 OR MIT` | 1 | `bytemuck` 1.23.1 |

the root package is separately `AGPL-3.0-or-later`. the active `imagequant` crate declares GPL-3.0-or-later; retain the exact upstream license file and notice for any later distribution review. a filename scan of the downloaded active crate source found an obvious license/copying/notice file in 46 of 47 third-party crates. `gif-dispose` 5.0.1 declares `MIT OR Apache-2.0`, but its published crate archive and official [`v5.0.1` source commit](https://github.com/kornelski/image-gif-dispose/tree/e50dcfbd38056d75184720e6c45daf23db16cecb) contain no separate license or notice file. the exact source, missing license artifacts, canonical license texts, and notice questions are recorded in the [dependency notice follow-up](#follow-up-gif-dispose-and-pngquant-notices-2026-10-24). this scan checks file presence by name only, not completeness, copyright notices, or license compatibility.

the lockfile includes optional FFmpeg packages and a patched `ffmpeg-sys-next` git source, but they do not appear in the default-feature `aarch64-apple-darwin` normal/build dependency tree. the built binary's `otool -L` output confirms that no FFmpeg library is linked; source feature inspection alone would not establish binary linkage.

## follow-up: gif-dispose and pngquant notices — 2026-10-24

### `gif-dispose` 5.0.1

the active dependency is pinned in Gifski's `Cargo.lock` with crates.io checksum `5e1aa07391f3d9c279f388cea6faf291555dd891df59bed01d4378583df946ac`. the locally cached `.crate` archive has the same SHA-256. its `.cargo_vcs_info.json` identifies upstream commit `e50dcfbd38056d75184720e6c45daf23db16cecb`; the official repository tree at that commit contains the manifest, readme, source, examples, and Cargo metadata, but no `LICENSE*`, `COPYING*`, or `NOTICE*` file. the cached archive has the same absence. the source `Cargo.toml` SHA-256 is `590fbfc4c55592f768e1b2a904a4f75008067857c973eb2e6389dda89f5652c7`; it declares `MIT OR Apache-2.0` and names `Kornel Lesiński <kornel@geekhood.net>` as author. the pinned source commit is authored by Kornel on 2024-07-09. neither the manifest nor source files provide an explicit copyright notice or copyright year.

authoritative text references are the [SPDX MIT license text](https://spdx.org/licenses/MIT.html) and the [Apache License 2.0 text](https://www.apache.org/licenses/LICENSE-2.0.txt). the MIT text requires the copyright and permission notices in copies or substantial portions; its canonical text contains year and copyright-holder placeholders. Apache-2.0 requires a copy of the license and retention of applicable source copyright, patent, trademark, and attribution notices; section 4(d)'s extra NOTICE-file condition is not triggered by a NOTICE file in this crate, because none was found. the author field is not an explicit license copyright notice, so this audit does not fill in a year or assume that the author field supplies the missing notice. obtain the publisher's exact license and copyright information before preparing notices. the manifest's dual-license expression does not make this audit a compatibility or redistribution decision.

### pngquant publisher notice in the active `imagequant` crate

the active locked `imagequant` 4.4.1 archive has Cargo.lock checksum and archive SHA-256 `caf5d73b959dfbe5d6b5cd3ca8de5265c7bc58297f20560a60a1d2ba6a19991f`. its packaged `COPYRIGHT` file has SHA-256 `6c131d200c9d383334c764474935faee2707164674be04e3ef7650731cbe7c9b`; `.cargo_vcs_info.json` points to source commit `24e2956a37cd7ad1f4b81c0e20318e3239eb71dc`. `Cargo.toml` explicitly includes `COPYRIGHT` in the crate package.

the [Gifski publisher's license/notices page](https://gif.ski/license.html) says the libimagequant lineage requires the displayed pngquant notice. it contains the Jef Poskanzer permission notice and a separate Greg Roelofs copyright, redistribution conditions, and disclaimer, and credits Stefan Schneider for the underlying idea. the exact active `imagequant` `COPYRIGHT` file contains the Jef permission notice and a Greg Roelofs copyright line, but it is not a verbatim copy of the publisher page: the page's Greg terms and Stefan attribution are not present in that file, and the copyright-year formatting differs. the page itself says its copyright/permission notice must accompany copies/supporting documentation and that binary redistribution reproduces the other notice's copyright, conditions, and disclaimer in documentation or other materials. retain the exact active crate `COPYRIGHT` and resolve whether/how to include the full publisher-published text in the final source and app notices; no page capture or page-content checksum was saved in this audit.

### recorded artifacts and open questions

| item | provenance/checksum | status |
| --- | --- | --- |
| `gif-dispose` 5.0.1 crate archive | Cargo.lock checksum and local archive SHA-256 `5e1aa07391f3d9c279f388cea6faf291555dd891df59bed01d4378583df946ac` | source pinned; no standalone license, copyright, copying, or notice file in crate archive |
| `gif-dispose` upstream tree | commit `e50dcfbd38056d75184720e6c45daf23db16cecb`; source `Cargo.toml` SHA-256 `590fbfc4c55592f768e1b2a904a4f75008067857c973eb2e6389dda89f5652c7` | manifest has dual-license expression and author field; exact copyright year/holder notice missing |
| canonical MIT and Apache-2.0 text | [SPDX MIT](https://spdx.org/licenses/MIT.html); [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0.txt) | authoritative text located; no exact crate-associated license files or completed notice texts available |
| active `imagequant` 4.4.1 crate | Cargo.lock checksum and archive SHA-256 `caf5d73b959dfbe5d6b5cd3ca8de5265c7bc58297f20560a60a1d2ba6a19991f`; source commit `24e2956a37cd7ad1f4b81c0e20318e3239eb71dc` | packaged `COPYRIGHT` present; hash `6c131d200c9d383334c764474935faee2707164674be04e3ef7650731cbe7c9b` |
| publisher pngquant notice | [gif.ski license/notices](https://gif.ski/license.html) | obligation and text located; no saved page capture/hash; packaged `COPYRIGHT` differs from the displayed notice |

remaining release questions: obtain the exact `gif-dispose` license files and copyright notice from its publisher, or otherwise get an authoritative written statement identifying the complete license text and notice for the pinned release; determine the notice presentation with qualified review; retain and present the exact active `imagequant` `COPYRIGHT` and resolve inclusion of the publisher's additional notice text. none of these findings clears redistribution or evaluates overall license compatibility.

## exact inspection commands and build status

tag refs were checked read-only:

```text
$ git ls-remote https://github.com/ImageOptim/gifski.git refs/tags/1.34.0 'refs/tags/1.34.0^{}' refs/tags/1.35.0 'refs/tags/1.35.0^{}'
072a09c2364a07266bf05d7bfa7361bcc28381e0  refs/tags/1.34.0
1060eab4500a20f27e2fa3ab7e85473d0e921cbd  refs/tags/1.34.0^{}
```

the pinned-source inspection commands were:

```sh
git clone --filter=blob:none --no-checkout --depth 1 --branch 1.34.0 https://github.com/ImageOptim/gifski.git /private/tmp/gifferent-gifski-1.34.0-src
git -C /private/tmp/gifferent-gifski-1.34.0-src checkout --detach 1060eab4500a20f27e2fa3ab7e85473d0e921cbd
git -C /private/tmp/gifferent-gifski-1.34.0-src rev-parse HEAD
shasum -a 256 Cargo.lock Cargo.toml LICENSE
cargo metadata --manifest-path /private/tmp/gifferent-gifski-1.34.0-src/Cargo.toml --locked --format-version 1
cargo tree --manifest-path /private/tmp/gifferent-gifski-1.34.0-src/Cargo.toml --locked --target aarch64-apple-darwin --edges normal,build --format '{p}'
```

the build used the task-specific environment below and kept target output outside the source checkout:

```sh
PATH=/private/tmp/gifferent-cargo-home/bin:/private/tmp/gifferent-rustup-home/toolchains/1.85.0-aarch64-apple-darwin/bin:/usr/bin:/bin:/usr/sbin:/sbin \
RUSTUP_HOME=/private/tmp/gifferent-rustup-home \
CARGO_HOME=/private/tmp/gifferent-cargo-home \
CARGO_TARGET_DIR=/private/tmp/gifski-target-1.34.0 \
cargo build --manifest-path /private/tmp/gifferent-gifski-1.34.0-src/Cargo.toml --release --locked
```

the build exited 0; the complete output is `/private/tmp/gifski-build-1.34.0.log`.

## remaining distribution evidence

the [cross-candidate package license evidence report](encoder-package-license-evidence-2026-10-24.md) records the specific `gif-dispose` and pngquant notice gaps found here and source-linked evidence for the Homebrew ImageMagick 7.1.2-34 candidate. it does not select an encoder or clear either build for distribution.

- [x] run the pinned release build and retain the full build log and exact command.
- [x] record binary SHA-256, `file`/`lipo`, `otool -L`, `gifski --version`, and complete `gifski --help` output; no FFmpeg-linked library is present.
- [ ] obtain and archive the exact `gif-dispose` license/copyright text and resolve publisher pngquant notice presentation as recorded in the [dependency notice follow-up](#follow-up-gif-dispose-and-pngquant-notices-2026-10-24); complete the remaining active-crate license and notice review before distribution.
- [x] run the two-candidate comparison across all four profiles at the approved 35% ImageMagick diffusion amount; see the [comparison report](gifski-magick-35-2026-10-24.md).
- [x] record the architect's native-size review of mostly-static and high-motion samples; both reviewed samples hold against the floor. the full multi-path encoder matrix, broader 2× review, distribution review, and candidate selection remain open; these findings do not select an encoder.

## upstream sources

- [official 1.34.0 release](https://github.com/ImageOptim/gifski/releases/tag/1.34.0) and [release list](https://github.com/ImageOptim/gifski/releases) — release and latest-version status.
- [official tag and commit](https://github.com/ImageOptim/gifski/commit/1060eab4500a20f27e2fa3ab7e85473d0e921cbd), [Cargo.toml](https://github.com/ImageOptim/gifski/blob/1060eab4500a20f27e2fa3ab7e85473d0e921cbd/Cargo.toml), [Cargo.lock](https://github.com/ImageOptim/gifski/blob/1060eab4500a20f27e2fa3ab7e85473d0e921cbd/Cargo.lock), and [license](https://github.com/ImageOptim/gifski/blob/1060eab4500a20f27e2fa3ab7e85473d0e921cbd/LICENSE) — pinned source and build inputs.
- [gifski README](https://github.com/ImageOptim/gifski/blob/1060eab4500a20f27e2fa3ab7e85473d0e921cbd/README.md) — documented build and optional video support.
- [`gif-dispose` 5.0.1 manifest](https://github.com/kornelski/image-gif-dispose/blob/e50dcfbd38056d75184720e6c45daf23db16cecb/Cargo.toml) and [source tree](https://github.com/kornelski/image-gif-dispose/tree/e50dcfbd38056d75184720e6c45daf23db16cecb) — declared dual license and absence of standalone license/notice files in the pinned source.
- [SPDX MIT license text](https://spdx.org/licenses/MIT.html) and [Apache License 2.0 text](https://www.apache.org/licenses/LICENSE-2.0.txt) — authoritative canonical license texts, not copied dependency artifacts.
- [libimagequant 4.4.1 `COPYRIGHT`](https://github.com/ImageOptim/libimagequant/blob/24e2956a37cd7ad1f4b81c0e20318e3239eb71dc/COPYRIGHT), [upstream project](https://github.com/ImageOptim/libimagequant), and [publisher license/notices](https://gif.ski/license.html) — active dependency copyright file and pngquant notice sources.
