# Gifski 1.34.0 third-party license materials

This directory contains source license and notice files for the Gifski 1.34.0 CLI candidate at commit `1060eab4500a20f27e2fa3ab7e85473d0e921cbd`. The active dependency graph was generated with `cargo tree --locked --target aarch64-apple-darwin --edges normal,build`; it contains 47 third-party crates. FFmpeg/video dependencies are not active in this graph. The pinned `Cargo.toml`, `Cargo.lock`, graph output, and publisher-page capture are in `source-evidence/`.

The full upstream Gifski license is in `gifski/LICENSE`. For `gif-dispose` 5.0.1, this project elects its declared Apache-2.0 option; the canonical text is included under that crate. For crates offering multiple licenses, all license files shipped in each exact crate archive are retained. The canonical GPL-3.0 text is included for `imagequant`, whose crate archive provides its `COPYRIGHT` file but not the full license text. `imagequant/COPYRIGHT` is retained with the separately published pngquant notice.

The pngquant notice was captured from <https://gif.ski/license.html> on 2026-10-29. SHA-256 of the captured HTML: `dfdb14092ce04de8d71670316dbe222dededeb3ffc07bbf6c8448998dec326f8`. The text file preserves the notice wording; whitespace was normalized for readability. The recorded lockfile SHA-256 is `d407a44d19ad1527baccdc5a07477cdba2872dc60bb09f2c524503dd26a3ce2f`; the manifest SHA-256 is `5738d2ed632ece91a87a129598c180b866b7133344c8bbe732dd13f18ef640ec`.

| crate | declared license | retained source files |
| --- | --- | --- |
| `anstream 0.6.19` | `MIT OR Apache-2.0` | `crates/anstream-0.6.19/LICENSE-APACHE`, `crates/anstream-0.6.19/LICENSE-MIT` |
| `anstyle 1.0.11` | `MIT OR Apache-2.0` | `crates/anstyle-1.0.11/LICENSE-APACHE`, `crates/anstyle-1.0.11/LICENSE-MIT` |
| `anstyle-parse 0.2.7` | `MIT OR Apache-2.0` | `crates/anstyle-parse-0.2.7/LICENSE-APACHE`, `crates/anstyle-parse-0.2.7/LICENSE-MIT` |
| `anstyle-query 1.1.3` | `MIT OR Apache-2.0` | `crates/anstyle-query-1.1.3/LICENSE-APACHE`, `crates/anstyle-query-1.1.3/LICENSE-MIT` |
| `arrayvec 0.7.6` | `MIT OR Apache-2.0` | `crates/arrayvec-0.7.6/LICENSE-APACHE`, `crates/arrayvec-0.7.6/LICENSE-MIT` |
| `autocfg 1.5.0` | `Apache-2.0 OR MIT` | `crates/autocfg-1.5.0/LICENSE-APACHE`, `crates/autocfg-1.5.0/LICENSE-MIT` |
| `bytemuck 1.23.1` | `Zlib OR Apache-2.0 OR MIT` | `crates/bytemuck-1.23.1/LICENSE-APACHE`, `crates/bytemuck-1.23.1/LICENSE-MIT`, `crates/bytemuck-1.23.1/LICENSE-ZLIB` |
| `cfg-if 1.0.1` | `MIT OR Apache-2.0` | `crates/cfg-if-1.0.1/LICENSE-APACHE`, `crates/cfg-if-1.0.1/LICENSE-MIT` |
| `clap 4.5.41` | `MIT OR Apache-2.0` | `crates/clap-4.5.41/LICENSE-APACHE`, `crates/clap-4.5.41/LICENSE-MIT` |
| `clap_builder 4.5.41` | `MIT OR Apache-2.0` | `crates/clap_builder-4.5.41/LICENSE-APACHE`, `crates/clap_builder-4.5.41/LICENSE-MIT` |
| `clap_lex 0.7.5` | `MIT OR Apache-2.0` | `crates/clap_lex-0.7.5/LICENSE-APACHE`, `crates/clap_lex-0.7.5/LICENSE-MIT` |
| `colorchoice 1.0.4` | `MIT OR Apache-2.0` | `crates/colorchoice-1.0.4/LICENSE-APACHE`, `crates/colorchoice-1.0.4/LICENSE-MIT` |
| `crc32fast 1.5.0` | `MIT OR Apache-2.0` | `crates/crc32fast-1.5.0/LICENSE-APACHE`, `crates/crc32fast-1.5.0/LICENSE-MIT` |
| `crossbeam-channel 0.5.15` | `MIT OR Apache-2.0` | `crates/crossbeam-channel-0.5.15/LICENSE-APACHE`, `crates/crossbeam-channel-0.5.15/LICENSE-MIT`, `crates/crossbeam-channel-0.5.15/LICENSE-THIRD-PARTY` |
| `crossbeam-deque 0.8.6` | `MIT OR Apache-2.0` | `crates/crossbeam-deque-0.8.6/LICENSE-APACHE`, `crates/crossbeam-deque-0.8.6/LICENSE-MIT` |
| `crossbeam-epoch 0.9.18` | `MIT OR Apache-2.0` | `crates/crossbeam-epoch-0.9.18/LICENSE-APACHE`, `crates/crossbeam-epoch-0.9.18/LICENSE-MIT` |
| `crossbeam-utils 0.8.21` | `MIT OR Apache-2.0` | `crates/crossbeam-utils-0.8.21/LICENSE-APACHE`, `crates/crossbeam-utils-0.8.21/LICENSE-MIT` |
| `dunce 1.0.5` | `CC0-1.0 OR MIT-0 OR Apache-2.0` | `crates/dunce-1.0.5/LICENSE` |
| `either 1.15.0` | `MIT OR Apache-2.0` | `crates/either-1.15.0/LICENSE-APACHE`, `crates/either-1.15.0/LICENSE-MIT` |
| `flate2 1.1.2` | `MIT OR Apache-2.0` | `crates/flate2-1.1.2/LICENSE-APACHE`, `crates/flate2-1.1.2/LICENSE-MIT` |
| `gif 0.13.3` | `MIT OR Apache-2.0` | `crates/gif-0.13.3/LICENSE-APACHE`, `crates/gif-0.13.3/LICENSE-MIT` |
| `gif-dispose 5.0.1` | `MIT OR Apache-2.0` | `crates/gif-dispose-5.0.1/LICENSE-APACHE-2.0.txt` |
| `imagequant 4.4.1` | `GPL-3.0-or-later` | `crates/imagequant-4.4.1/COPYRIGHT`, `crates/imagequant-4.4.1/LICENSE-GPL-3.0-or-later.txt` |
| `imgref 1.11.0` | `CC0-1.0 OR Apache-2.0` | `crates/imgref-1.11.0/LICENSE-APACHE`, `crates/imgref-1.11.0/LICENSE-CC0` |
| `is_terminal_polyfill 1.70.1` | `MIT OR Apache-2.0` | `crates/is_terminal_polyfill-1.70.1/LICENSE-APACHE`, `crates/is_terminal_polyfill-1.70.1/LICENSE-MIT` |
| `libc 0.2.174` | `MIT OR Apache-2.0` | `crates/libc-0.2.174/LICENSE-APACHE`, `crates/libc-0.2.174/LICENSE-MIT` |
| `libz-rs-sys 0.5.1` | `Zlib` | `crates/libz-rs-sys-0.5.1/LICENSE` |
| `lodepng 3.12.1` | `Zlib` | `crates/lodepng-3.12.1/COPYRIGHT` |
| `loop9 0.1.5` | `MIT` | `crates/loop9-0.1.5/LICENSE` |
| `natord 1.0.9` | `MIT` | `crates/natord-1.0.9/LICENSE.txt` |
| `num-traits 0.2.19` | `MIT OR Apache-2.0` | `crates/num-traits-0.2.19/LICENSE-APACHE`, `crates/num-traits-0.2.19/LICENSE-MIT` |
| `once_cell 1.21.3` | `MIT OR Apache-2.0` | `crates/once_cell-1.21.3/LICENSE-APACHE`, `crates/once_cell-1.21.3/LICENSE-MIT` |
| `ordered-channel 1.2.0` | `MIT OR Apache-2.0` | `crates/ordered-channel-1.2.0/LICENSE` |
| `pbr 1.1.1` | `MIT` | `crates/pbr-1.1.1/LICENSE.md` |
| `quick-error 2.0.1` | `MIT/Apache-2.0` | `crates/quick-error-2.0.1/LICENSE-APACHE`, `crates/quick-error-2.0.1/LICENSE-MIT` |
| `rayon 1.10.0` | `MIT OR Apache-2.0` | `crates/rayon-1.10.0/LICENSE-APACHE`, `crates/rayon-1.10.0/LICENSE-MIT` |
| `rayon-core 1.12.1` | `MIT OR Apache-2.0` | `crates/rayon-core-1.12.1/LICENSE-APACHE`, `crates/rayon-core-1.12.1/LICENSE-MIT` |
| `resize 0.8.8` | `MIT` | `crates/resize-0.8.8/LICENSE` |
| `rgb 0.8.51` | `MIT` | `crates/rgb-0.8.51/LICENSE` |
| `strsim 0.11.1` | `MIT` | `crates/strsim-0.11.1/LICENSE` |
| `thread_local 1.1.9` | `MIT OR Apache-2.0` | `crates/thread_local-1.1.9/LICENSE-APACHE`, `crates/thread_local-1.1.9/LICENSE-MIT` |
| `utf8parse 0.2.2` | `Apache-2.0 OR MIT` | `crates/utf8parse-0.2.2/LICENSE-APACHE`, `crates/utf8parse-0.2.2/LICENSE-MIT` |
| `weezl 0.1.10` | `MIT OR Apache-2.0` | `crates/weezl-0.1.10/LICENSE-APACHE`, `crates/weezl-0.1.10/LICENSE-MIT` |
| `wild 2.2.1` | `Apache-2.0 OR MIT` | `crates/wild-2.2.1/LICENSE` |
| `y4m 0.8.0` | `MIT` | `crates/y4m-0.8.0/LICENSE` |
| `yuv 0.1.9` | `BSD-2-Clause` | `crates/yuv-0.1.9/LICENSE` |
| `zlib-rs 0.5.1` | `Zlib` | `crates/zlib-rs-0.5.1/LICENSE` |

This is an engineering notice inventory, not legal advice or release clearance. Before bundling, verify the exact binary build graph, include these files in the app notice presentation, retain corresponding source/build materials required by applicable licenses, and re-run the audit after any version or feature change.
