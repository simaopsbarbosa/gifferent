# decisions and questions

## execution authority confirmed on 2026-10-22

- the lead engineer owns engineering choices, task order, agent assignments, integration, repository setup, CI/CD, and quality gates. the architect retains approval of changes to settled experience, final visual and sound identity, and release policy.
- deliver the complete documented first release through tested iterations described in [delivery-plan.md](delivery-plan.md). the planning stage is complete and implementation has begun.
- the release plan may depend on Apple Developer access and a real-Mac acceptance pass supplied at the release gate. neither is assumed available for initial development.

## recording and cleanup confirmed on 2026-10-22

- if a selected window is minimized or closed during recording, stop capture with a clear message and keep any usable frames as a partial result for preview or discard. if no usable frame exists, show an actionable error and clean up the session.
- when a selected window moves to another display, continue following that window. the one-monitor limit still applies to region and display capture.
- keep completed preview media only while its preview is active. remove temporary media after the preview closes following export or after confirmed discard. clear orphaned preview media on the next launch after a crash; an exported file remains intact.
- show a thin, high-contrast recording outline just outside a selected region or window, with a small `recording` label at its top edge. adapt it to light and dark backgrounds and keep it out of the GIF.
- if the selected display disconnects during recording, stop with a clear message and keep usable captured frames as a partial result. if no usable frame exists, show an actionable error and clean up.
- global shortcut registration cannot prove delivery because macOS can let another app use the same chord. settings must ask the user to press each shortcut from another app and warn that it is unverified until gifferent receives it.
- use the development MacBook Air (Apple M2, 8 GB) as the first release performance reference, currently macOS 27.0.1 (build 26A434), with low power mode off. publish the synthetic fixtures and report median and p90 timing; record every additional Mac separately. re-record the OS and power mode for each benchmark run rather than treating this snapshot as permanent.

## recording selection flow confirmed on 2026-10-24

- when `⌃⌥R` opens target selection because no selection exists, confirming the target starts recording immediately. the menu's separate `select capture…` action only stores a selection.

## editing and clipboard acceptance confirmed on 2026-10-24

- trim uses two timeline handles to set the beginning and end of a recording.
- playback speed uses a continuous slider from 0.5× to 2× in 0.1× steps, centered at 1×.
- the real-Mac animated clipboard paste acceptance test covers GitHub only. other destinations are outside this first-release clipboard compatibility gate.

## compression behavior confirmed on 2026-10-24

- the minimum acceptable compression quality keeps text legible at native scale, keeps cursor edges clear, and has no distracting banding or flicker in gradients. minor differences visible only at 2× are acceptable.
- the dithering slider controls ImageMagick's documented `dither:diffusion-amount` from 0% to 100% in 5% steps, with a default of 35%. this product choice does not select ImageMagick as the release encoder; the pinned build must prove the setting changes output, and candidate, quality, performance, and distribution gates remain open.

## confirmed by the architect on 2026-10-20

- macOS 14+, direct notarized download, menu bar only, background hotkeys, native SwiftUI UI.
- `⌃⌥G` opens a full-screen selection overlay. `⌃⌥R` starts and stops recording; without a selection it opens selection. both are configurable with conflict warnings.
- one monitor at a time; select a display, one window, or a movable and resizable region. corner magnifier during drag. the selected window is followed when it moves or changes size. subtle recording frame stays out of the GIF. restore the last valid selection with quick reselect.
- GIF only; no captured sound. cursor included by default but configurable. initial target 24 fps. typical recording under 30 seconds; warn about long or large recording but do not silently stop it.
- floating preview after stop; original retained behind a back action when viewing compression. include metadata, copy, save dialog, discard, and compress. `⌘C` copies an animated GIF suitable for pasting into GitHub; `⌘S` saves. confirm before closing an unexported preview.
- trim, playback speed that changes duration, and forever/once loop modes in the first release.
- compression runs locally through bundled existing command-line tooling. slider changes dithering strength. resolution: original, 75%, 50%, 25%. destination presets: Discord and GitHub. Slack is excluded until a useful size goal is defined. show logos and size limits under `optimize for:`, target slightly below the limit, search across resolution, frame rate, palette, and dithering. prefer the smallest acceptable file under target; show best attempt plus warning otherwise.
- brand working name `gifferent`; the first mark candidate is a simple geometric loop frame, mostly monochrome with warm orange accent; mood references Augusta Labs and Cloudflare UI; small occasional brand marks in capture UI. sound is subtle and optional.
- prose is lowercase except proper names. all features need unit, integration, and automated end-to-end acceptance tests. CI gates build, tests, format, and lint; release includes real-Mac manual acceptance.
- public project under AGPL-3.0-or-later; captured pixels never leave the Mac. benchmark speed goals on a baseline Apple Silicon laptop. clear partial recordings after a crash rather than restoring them. when a detail is undecided, record it and ask the architect.

## questions to resolve before affected implementation

1. **brand asset:** develop loop-frame sketches with a warm orange accent. the exact artwork, orange values, motion signature, and sound palette still need architect review.
2. **bundled tool license:** verify which candidate CLIs can be distributed with an AGPL-3.0-or-later app and document their notices and source obligations before packaging.
3. **quality review evidence:** collect and review representative comparison samples against the approved minimum quality floor before selecting size-goal search settings.
4. **clipboard representation:** verify the chosen pasteboard representations by pasting an animated GIF into GitHub on a real Mac. a successful local pasteboard write alone does not establish destination compatibility.

## research notes, not product decisions

- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos) supports display, app, and window filters. selected-window capture fits the architect's answer.
- [gifski](https://github.com/ImageOptim/gifski/blob/main/README.md) uses temporal dithering and has a C API, but the architect asked for a bundled CLI. [gifsicle](https://github.com/kohler/gifsicle/blob/master/gifsicle.1) exposes dither methods including Floyd–Steinberg, Atkinson, and ordered variants. performance and visual quality must be benchmarked before selecting one or both.
- the installed exploratory ImageMagick build changed encoded pixels and output size at 0%, 35%, and 70% diffusion on sparse samples from two synthetic fixtures; see the [prototype report](Benchmarks/imagemagick-dither-control-prototype-2026-10-24.md). this confirms only that the slider mapping has an observable effect in that build.
- destination file limits can change. the limits quoted in [mvp.md](mvp.md) are a 2026-10-20 research snapshot and need verification before release.
