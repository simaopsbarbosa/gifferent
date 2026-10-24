# architecture and experiments

## initial stack

- language and build: Swift 6 with an Xcode macOS application project, deployment target macOS 14. the foundation pins Xcode 26.2 (build 17C52) locally and on the `macos-26` CI runner; update both deliberately after verification.
- UI: SwiftUI scenes and controls, including `MenuBarExtra`; narrow AppKit windows or views where the full-screen selection overlay, floating preview, drag magnifier, global event behavior, or pasteboard needs them. use native accessibility and appearance APIs.
- capture: ScreenCaptureKit for display and window streams, with a display crop for region recording; public Core Graphics permission APIs for preflight and request. keep selection geometry in display coordinates and test scale factors and screen changes.
- hotkeys: a dedicated Carbon `RegisterEventHotKey` adapter with setting persistence and start/stop state. nonexclusive registration cannot detect another app using the same chord, so settings distinguish registered from observed delivery and warn until the user tests the shortcut from another app. duplicate chords within gifferent and system registration errors are rejected immediately.
- pipeline: timestamped frames enter a bounded queue; encoding and optimization run off the main actor; a small temporary workspace holds the active session. preview closure after export and confirmed discard clean up temporary data. on launch after a crash, delete unfinished session data rather than restoring it.
- lifecycle: keep completed temporary media while its preview is active, then delete it when the preview closes after export or is discarded. delete orphaned preview media on launch after a crash. preserve exported files. stop a tracked-window recording when the window closes or is minimized, retaining a partial result only when usable frames exist; continue following the window across displays. stop display recording on display disconnect with the same partial-result rule.
- recording frame: place a thin, high-contrast outline outside a region or window boundary with a small `recording` label at its top edge. use a separate overlay excluded from captured pixels, and adapt contrast to light and dark backgrounds.
- the frame uses a transparent, nonactivating, click-through AppKit panel with SwiftUI drawing. add the visible panel to the app's accessibility windows so assistive technology can discover its `recording` label, then remove it when hidden. map region geometry from display-local top-left points into AppKit screen coordinates. track the selected window's live bounds and reposition the panel as the window moves or resizes. full-display capture has no outside edge and does not show the frame.
- encoder candidates: benchmark complete `gifski`, ImageMagick, and native ImageIO paths as described in [candidate research](Benchmarks/encoder-candidates.md). `gifski` is the provisional lead; the exact binary, usable dither control, quality, and redistribution obligations remain open. keep `gifsicle` research-only while its GPL-2.0-only distribution question is unresolved. isolate invocation, capture stdout/stderr, validate output, and allow cancellation.
- tests: Swift Testing or XCTest for logic and component integration, XCTest UI tests for acceptance, and fixture-based real CLI tests. keep adapters injectable so tests can control time, capture frames, files, and subprocess outcomes. the foundation uses a debug-only AppKit test window to show the same SwiftUI menu content because hosted CI exposes a zero-size status item that XCTest cannot click. selection UI tests use a synthetic display snapshot in debug test mode, without requesting screen access. verify actual menu bar, permission, hotkey, and overlay interaction on a real Mac. neither test seam runs in normal launches.
- checks: `swift-format`, `xcodebuild`, and GitHub Actions on macOS. release automation signs the app and nested tools, notarizes the artifact, and verifies a clean-machine launch.

## current implementation boundary

the recording iteration connects the menu and `⌃⌥R` action to a ScreenCaptureKit stream, bounded newest-frame transport, target-loss monitor, and quota-limited temporary workspace. the workspace is private under the user's cache directory, capped at 512 mib per session, and preserves at least 64 mib of free space. launch cleanup removes orphaned recording sessions; selecting a target from the record action starts capture immediately, while `select capture…` only stores a selection. region targets retain their selected display geometry and are checked against the current display before stream startup; window capture scales resized content to its initial output size. stream preparation is separate from capture start, so the coordinator installs one sequential PNG frame consumer before samples can arrive. concurrent stop requests share one finalization task, which finishes frame delivery, drains the consumer, and then retains usable user-stopped or target-loss sessions. permission loss, stream failure, and frame processing or storage errors discard the session and report failure. captured PNG sessions currently offer discard only; the menu explicitly says that GIF preview is not available yet. the app does not yet connect recording to a GIF encoder, playable preview, clipboard, or export. stream behavior, frame exclusion, and window movement and resizing still need real-Mac verification. playable GIF validation belongs to the encoding seam before a preview can be shown.

## performance experiments before choosing a pipeline

1. build representative fixtures: mostly static UI, fast scrolling, video-like motion, small region, full display, ten seconds, and thirty seconds. include light/dark UI and fine text.
2. compare streaming encode during recording with encode after stop. measure stop-to-usable-preview, CPU, memory, temporary bytes, final GIF bytes, and dropped frames. the under-two-second preview goal may require incremental encoding; prove it on the [selected performance reference](Benchmarks/environment.md), recording its actual configuration for each run.
3. compare complete `gifski`, ImageMagick, and native ImageIO paths at equal output dimensions and frame timing. keep a `gifsicle` path research-only until its distribution license is resolved. inspect text legibility, temporal artifacts, and dither character alongside bytes and time.
4. measure size-goal search: try the cheapest transformations first, cache intermediate results where safe, stop when the result meets the target, and cap work so the UI never looks frozen. the search order is an experiment, not a fixed requirement.
5. measure the overlay and magnifier at 1× and 2× scaling, with separate displays, and verify that the overlay cannot enter captured frames.

## design constraints

- 24 fps is the initial target, not a guarantee of every system or scene. preserve honest timing and report dropped frames in diagnostics.
- display and region streams exclude gifferent's application in their ScreenCaptureKit filters. selected-window streams include only the chosen window, so the separate overlay window is outside that filter. do not rely on `NSWindow.sharingType` to omit content; Apple's current documentation marks that setting legacy. verify on a real Mac that the overlay never appears in captured frames.
- the dithering slider directly controls dither strength. size presets may also adjust frame rate, palette, and resolution to meet their target; make the effective settings visible so the result is understandable.
- do not block first preview on secondary optimization if a playable original can appear sooner. show truthful processing state until the final GIF is ready for copy or save.
- avoid automatic capture or background pixel access before the user invokes the recording flow and grants permission.

## references

- [Apple ScreenCaptureKit capture sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)
- [Apple SwiftUI menu bar extra](https://developer.apple.com/documentation/swiftui/menubarextra)
- [Apple testing guidance](https://developer.apple.com/documentation/xcode/adding-tests-to-your-xcode-project)
- [gifski CLI and library](https://github.com/ImageOptim/gifski)
- [gifsicle options and dithering methods](https://github.com/kohler/gifsicle/blob/master/gifsicle.1)
