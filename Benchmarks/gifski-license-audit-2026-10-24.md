# gifski 1.34.0 license audit

## scope and result

this is a packaging evidence note, not legal clearance. the pinned Gifski tag is `1.34.0` at commit `1060eab4500a20f27e2fa3ab7e85473d0e921cbd`. the publisher's manifest enables the `binary` and `gifsicle` defaults. the lockfile contains 103 packages, including optional video and development dependencies; this list alone does not identify the active transitive graph.

these package manifests were checked for declarations relevant to the default CLI feature set:

| package | version | declared license |
| --- | --- | --- |
| gifski | 1.34.0 | AGPL-3.0-or-later |
| gif | 0.13.3 | MIT OR Apache-2.0 |
| gif-dispose | 5.0.1 | MIT OR Apache-2.0 |
| imagequant | 4.4.1 | GPL-3.0-or-later |
| clap | 4.5.41 | MIT OR Apache-2.0 |
| yuv | 0.1.9 | BSD-2-Clause |
| y4m | 0.8.0 | MIT |
| pbr | 1.1.1 | MIT |
| lodepng | 3.12.1 | Zlib |
| wild | 2.2.1 | Apache-2.0 OR MIT |
| natord | 1.0.9 | MIT |
| dunce | 1.0.5 | CC0-1.0 OR MIT-0 OR Apache-2.0 |
| quick-error | 2.0.1 | MIT/Apache-2.0 |
| resize | 0.8.8 | MIT |
| rgb | 0.8.51 | MIT |
| crossbeam-channel | 0.5.15 | MIT OR Apache-2.0 |
| imgref | 1.11.0 | CC0-1.0 OR Apache-2.0 |
| loop9 | 0.1.5 | MIT |
| num-traits | 0.2.19 | MIT OR Apache-2.0 |
| crossbeam-utils | 0.8.21 | MIT OR Apache-2.0 |
| ordered-channel | 1.2.0 | MIT OR Apache-2.0 |

this is a partial package-manifest inventory, not a mechanically verified active transitive graph. `quick-error` uses a non-standard SPDX expression and requires normalization and text review. do not treat a license identifier as proof that all required texts and notices are present.

## blockers

- the cached `gif-dispose 5.0.1` crate declares `MIT OR Apache-2.0` but contains no license text. choose the declared Apache-2.0 option and include its canonical license text; do not use MIT without its required copyright notice. the final source and binary still need notice verification.
- the Gifski crate packaging rules omit the top-level `LICENSE`. build and distribute from the matching tagged source repository and retain its AGPL license and publisher notices, rather than relying only on the crate archive.
- the Gifski publisher documents historical pngquant notices. include the applicable notice material after confirming it against the exact source build.
- the active transitive dependency graph and every transitive license have not been verified. the audit environment has no configured Rust toolchain; `cargo tree` could not run.
- direct distribution needs an approved corresponding-source plan, complete license and notice bundle, pinned reproducible build, and signed/notarized executable audit.

## required build-time verification

on the pinned Rust builder, record the toolchain and run:

```sh
cargo tree --locked --target aarch64-apple-darwin --no-default-features --features binary,gifsicle
cargo metadata --locked --format-version 1 --filter-platform aarch64-apple-darwin
```

generate the SPDX inventory from resolved active packages and features. archive the lockfile, source commit, crate checksums, builder/toolchain versions, build script, source bundle, and all required license and notice texts. compare the executable's linked components and features to that inventory. obtain qualified review of bundling and corresponding-source obligations before enabling the CLI in a distributable app.

## primary sources

- [Gifski 1.34.0 release](https://github.com/ImageOptim/gifski/releases/tag/1.34.0)
- [pinned Gifski manifest](https://github.com/ImageOptim/gifski/blob/1.34.0/Cargo.toml)
- [pinned Gifski license](https://github.com/ImageOptim/gifski/blob/1.34.0/LICENSE)
- [gif-dispose 5.0.1 package](https://crates.io/crates/gif-dispose/5.0.1)
- [gif-dispose 5.0.1 source tag](https://github.com/kornelski/image-gif-dispose/tree/v5.0.1)
- [Gifski publisher's historical pngquant notices](https://gif.ski/license.html)
