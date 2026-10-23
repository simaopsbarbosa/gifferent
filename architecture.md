# architecture and experiments

## initial stack

- language and build: Swift 6 with an Xcode macOS application project, deployment target macOS 14. the foundation pins Xcode 26.2 (build 17C52) locally and on the `macos-26` CI runner; update both deliberately after verification.
- UI: SwiftUI scenes and controls, including `MenuBarExtra`; narrow AppKit windows or views where the full-screen selection overlay, floating preview, drag magnifier, global event behavior, or pasteboard needs them. use native accessibility and appearance APIs.
- capture: ScreenCaptureKit for display and window streams, with a display crop for region recording; public Core Graphics permission APIs for preflight and request. keep selection geometry in display coordinates and test scale factors and screen changes.
- hotkeys: a dedicated adapter with registration, conflict detection, setting persistence, and start/stop state. select the supported system mechanism after a prototype on macOS 14 and the current macOS release.
- pipeline: timestamped frames enter a bounded queue; encoding and optimization run off the main actor; a small temporary workspace holds the active session. preview closure after export and confirmed discard clean up temporary data. on launch after a crash, delete unfinished session data rather than restoring it.
- lifecycle: keep completed temporary media while its preview is active, then delete it when the preview closes after export or is discarded. delete orphaned preview media on launch after a crash. preserve exported files. stop a tracked-window recording when the window closes or is minimized, retaining a partial result only when usable frames exist; continue following the window across displays. stop display recording on display disconnect with the same partial-result rule.
- recording frame: place a thin, high-contrast outline outside a region or window boundary with a small `recording` label at its top edge. use a separate overlay excluded from captured pixels, and adapt contrast to light and dark backgrounds.
- encoder candidates: bundle an existing CLI. evaluate `gifski` for high-quality dithered encoding and `gifsicle` for lossless/lossy optimization and alternate dithering. isolate invocation, capture stdout/stderr, validate output, and allow cancellation. their published licenses are [AGPL-3.0-or-later](https://github.com/ImageOptim/gifski/blob/main/README.md) and [GPL-2.0 with an alternative commercial path](https://github.com/kohler/gifsicle), respectively. the project license is AGPL-3.0-or-later. review the obligations and compatibility of each bundled tool before distribution.
- tests: Swift Testing or XCTest for logic and component integration, XCTest UI tests for acceptance, and fixture-based real CLI tests. keep adapters injectable so tests can control time, capture frames, files, and subprocess outcomes. the foundation uses a debug-only AppKit test window to show the same SwiftUI menu content because hosted CI exposes a zero-size status item that XCTest cannot click; verify actual menu bar interaction on a real Mac. the window is never created in normal launches.
- checks: `swift-format`, `xcodebuild`, and GitHub Actions on macOS. release automation signs the app and nested tools, notarizes the artifact, and verifies a clean-machine launch.

## performance experiments before choosing a pipeline

1. build representative fixtures: mostly static UI, fast scrolling, video-like motion, small region, full display, ten seconds, and thirty seconds. include light/dark UI and fine text.
2. compare streaming encode during recording with encode after stop. measure stop-to-usable-preview, CPU, memory, temporary bytes, final GIF bytes, and dropped frames. the under-two-second preview goal may require incremental encoding; prove it on a baseline Apple Silicon laptop, with the exact model and configuration recorded before measurement.
3. compare `gifski` alone, `gifski` plus `gifsicle`, and a viable native baseline at equal output dimensions and frame timing. inspect text legibility, temporal artifacts, and dither character alongside bytes and time.
4. measure size-goal search: try the cheapest transformations first, cache intermediate results where safe, stop when the result meets the target, and cap work so the UI never looks frozen. the search order is an experiment, not a fixed requirement.
5. measure the overlay and magnifier at 1× and 2× scaling, with separate displays, and verify that the overlay cannot enter captured frames.

## design constraints

- 24 fps is the initial target, not a guarantee of every system or scene. preserve honest timing and report dropped frames in diagnostics.
- the dithering slider directly controls dither strength. size presets may also adjust frame rate, palette, and resolution to meet their target; make the effective settings visible so the result is understandable.
- do not block first preview on secondary optimization if a playable original can appear sooner. show truthful processing state until the final GIF is ready for copy or save.
- avoid automatic capture or background pixel access before the user invokes the recording flow and grants permission.

## references

- [Apple ScreenCaptureKit capture sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)
- [Apple SwiftUI menu bar extra](https://developer.apple.com/documentation/swiftui/menubarextra)
- [Apple testing guidance](https://developer.apple.com/documentation/xcode/adding-tests-to-your-xcode-project)
- [gifski CLI and library](https://github.com/ImageOptim/gifski)
- [gifsicle options and dithering methods](https://github.com/kohler/gifsicle/blob/master/gifsicle.1)
