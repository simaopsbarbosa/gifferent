# Gifski 1.34.0 helper

The bundled helper is built from the official Gifski 1.34.0 source at commit `1060eab4500a20f27e2fa3ab7e85473d0e921cbd`, using Rust 1.85.0 and the locked default CLI features. The build excludes optional FFmpeg support.

The committed universal binary SHA-256 is `e2ca0614ce3803e1963d4b48923b25e8c20fc4070873a526f1e151b652a87df6`. It contains `arm64` and `x86_64` slices and links only macOS system libraries. Rebuild it with `bash Scripts/build-gifski.sh`.

The complete license and notice inventory is in [`ThirdPartyNotices/Gifski-1.34.0`](../../ThirdPartyNotices/Gifski-1.34.0/README.md). Xcode embeds the helper in `Contents/MacOS` and signs it as nested code when signing is enabled.
