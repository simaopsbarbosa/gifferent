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

## recording preferences and warnings confirmed on 2026-10-24

- put the configurable cursor-inclusion setting in a separate “recording settings…” window reachable from the menu. include the cursor by default; let the user turn it off.
- warn once per recording after 30 seconds or when its session workspace reaches 75% of the 512 mib quota. keep recording, let the user dismiss the warning, and do not repeat it in that session.
- show the non-modal warning in the menu-bar app with an explicit dismiss action. do not interrupt capture or include the warning in captured pixels.

## brand exploration confirmed on 2026-10-24

- refine study c, the vertical loop, in a second round of monochrome mark studies. this does not approve final artwork, exact orange values, motion, or sound.
- after reviewing the second round, proceed with variant b, the vertical loop with directional ends, for final-art exploration. do not treat it as approved final artwork or infer orange, motion, or sound choices.
- after reviewing round three, move study 03, compact orbit, into detailed final-art review. this chooses a refinement direction only; final silhouette, exact orange values, motion, and sound remain unapproved.
- after reviewing the detail round, proceed with treatment 02, breathing room, toward final-art approval. the architect flagged its possible 16 px break for review; this does not approve final artwork, color, motion, or sound.
- after reviewing the final-art sheet, adjust the 16 px gap and continue palette exploration with warm orange `#D45D21`. this does not approve the exact gap, final mark, or palette; both remain provisional pending another accessible comparison and architect review.
- after reviewing the measured gap comparison, carry the 0.7 px gap at 16 px into palette and final-art exploration. this selects a study direction only; the final mark and exact palette remain unapproved.

## static brand mark approved on 2026-10-24

- this approval supersedes the provisional states recorded during brand exploration: use the static orange mark in [the production-mark review](Brand/Studies/production-mark-review/index.html), compact orbit 03, breathing-room treatment 02, a 0.7 px curve-to-tip gap at 16 px, and `#D45D21` direction tips on a monochrome frame and loop.
- use the light and dark SVG production assets at `Brand/mark-light.svg` and `Brand/mark-dark.svg`. keep the mark static; the optional motion study and sound are not approved.
- validate at real menu-bar sizes, materials, and accessibility settings on supported macOS versions before release.

## compression behavior confirmed on 2026-10-24

- the minimum acceptable compression quality keeps text legible at native scale, keeps cursor edges clear, and has no distracting banding or flicker in gradients. minor differences visible only at 2× are acceptable.
- original choice, superseded below: the architect approved an ImageMagick diffusion slider from 0% to 100% in 5% steps, default 35%. after full-path benchmarking, the architect replaced it with Gifski quality control.
- size goals target 90% of each published cap using decimal megabytes: 9 MB for GitHub image/GIF uploads and 18 MB for Discord's non-Nitro attachment cap. these are optimization targets, not guarantees; show the current cap and account caveat.
- use destination names with native symbols on the optimizer buttons. do not bundle third-party destination marks unless written permission is obtained.
- after reviewing the native-size animated examples for mostly-static UI and high-motion content in [the encoder review](Benchmarks/reviews/gifski-magick-35-2026-10-24/index.html), the architect confirmed that both samples hold against the approved quality floor. this is a visual-quality judgment for these samples, not an encoder selection or a claim that the full search matrix passes.

## Gifski quality control approved on 2026-10-24

- after reviewing the complete available-path benchmark, the architect approved replacing the ImageMagick diffusion slider with a Gifski quality slider from 1 to 100, defaulting to 90. use one-point slider steps and map the value directly to Gifski `--quality`.
- use Gifski 1.34.0 for backend integration and size-search prototyping. the search may vary resolution, sampled frame rate, and Gifski quality; Gifski owns palette generation. preserve the approved quality floor. this selection is conditional for direct distribution: the exact `gif-dispose` notice and complete bundled dependency/source obligations remain unresolved, so do not package or release the executable until those gates close.
- the four-profile full matrix and its resource measurements are in [the benchmark report](Benchmarks/gifski-magick-35-full-matrix-2026-10-24.md). the existing two-profile animated review passed the floor at quality 90; the four-profile still review adds spatial checks but does not establish flicker or full-animation quality.

## Quality-search floor confirmed on 2026-10-24

- after reviewing the animated [Gifski quality sweep](Benchmarks/reviews/gifski-quality-sweep-2026-10-24/index.html), the architect set quality 90 as the lowest value the automatic size search may use for now. the existing quality-90 animations remain the approved floor reference. keep the manual quality slider at 1–100; do not lower the automatic search floor without a later architect decision based on visual review.
- the sweep records quality 70, 80, 90, and 100 outputs for mostly-static and high-motion profiles. its measurements are evidence, not approval of qualities below 90; three-run timings are indicative only.

## Size-search resolution behavior confirmed on 2026-10-24

- the current resolution choice is the maximum size the automatic destination search may use. search that size and smaller choices only; do not upscale above the user's selection.
- sampled frame rates and reduced resolutions still need animated visual review against the approved quality floor before those combinations are accepted in the automatic candidate set.

## Size-search visual candidates pending review on 2026-10-24

- benchmark candidates are 24, 18, 12, and 8 fps across original, 75%, 50%, and 25% resolution, at Gifski quality 90. the approved quality-90 full-size 24 fps output is the comparison baseline.
- until the architect reviews the representative animated samples, keep the active automatic search at 24 fps and do not claim that reduced resolution or frame rate meets the approved quality floor. review all scales at 24 fps, all rates at original scale, and the joint 25%/8 fps corner before enabling those candidates.

## confirmed by the architect on 2026-10-20

- macOS 14+, direct notarized download, menu bar only, background hotkeys, native SwiftUI UI.
- `⌃⌥G` opens a full-screen selection overlay. `⌃⌥R` starts and stops recording; without a selection it opens selection. both are configurable with conflict warnings.
- one monitor at a time; select a display, one window, or a movable and resizable region. corner magnifier during drag. the selected window is followed when it moves or changes size. subtle recording frame stays out of the GIF. restore the last valid selection with quick reselect.
- GIF only; no captured sound. cursor included by default but configurable. initial target 24 fps. typical recording under 30 seconds; warn about long or large recording but do not silently stop it.
- floating preview after stop; original retained behind a back action when viewing compression. include metadata, copy, save dialog, discard, and compress. `⌘C` copies an animated GIF suitable for pasting into GitHub; `⌘S` saves. confirm before closing an unexported preview.
- trim, playback speed that changes duration, and forever/once loop modes in the first release.
- compression runs locally through a bundled existing command-line tool. the latest approved control is Gifski quality from 1 to 100, default 90. resolution: original, 75%, 50%, 25%. destination presets: Discord and GitHub; show destination names with native symbols, current published maximum, and the approved 90% target (9 MB GitHub, 18 MB Discord non-Nitro). Slack is excluded until a useful size goal is defined. search across resolution, sampled frame rate, and quality; prefer the smallest acceptable file under target and show the best attempt plus a warning otherwise. Gifski manages palette generation internally.
- brand working name `gifferent`; the first mark candidate is a simple geometric loop frame, mostly monochrome with warm orange accent; mood references Augusta Labs and Cloudflare UI; small occasional brand marks in capture UI. sound is subtle and optional.
- prose is lowercase except proper names. all features need unit, integration, and automated end-to-end acceptance tests. CI gates build, tests, format, and lint; release includes real-Mac manual acceptance.
- public project under AGPL-3.0-or-later; captured pixels never leave the Mac. benchmark speed goals on a baseline Apple Silicon laptop. clear partial recordings after a crash rather than restoring them. when a detail is undecided, record it and ask the architect.

## questions to resolve before affected implementation

1. **bundled tool license:** the candidate-level engineering screen is recorded in [the encoder license audit](Benchmarks/encoder-license-audit.md). exact source, dependency, and binary audits remain required before packaging; Gifsicle's distribution terms remain unresolved for this app bundle.
2. **encoder distribution:** Gifski 1.34.0 is approved for backend integration and search, but direct distribution remains blocked until its exact `gif-dispose` notice, complete dependency license/attribution texts, corresponding source obligations, pinned build provenance, and final bundle contents are verified. ImageMagick is not the release path; its measured time/resource costs and distributable dependency closure are recorded in the benchmark and package-evidence reports.
3. **clipboard representation:** verify the chosen pasteboard representations by pasting an animated GIF into GitHub on a real Mac. a successful local pasteboard write alone does not establish destination compatibility.

## research notes, not product decisions

- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos) supports display, app, and window filters. selected-window capture fits the architect's answer.
- [gifski](https://github.com/ImageOptim/gifski/blob/main/README.md) uses temporal dithering and has a C API, but the architect asked for a bundled CLI. [gifsicle](https://github.com/kohler/gifsicle/blob/master/gifsicle.1) exposes dither methods including Floyd–Steinberg, Atkinson, and ordered variants. performance and visual quality must be benchmarked before selecting one or both.
- the installed exploratory ImageMagick build changed encoded pixels and output size at 0%, 35%, and 70% diffusion on sparse samples from two synthetic fixtures; see the [prototype report](Benchmarks/imagemagick-dither-control-prototype-2026-10-24.md). this confirms only that the slider mapping has an observable effect in that build.
- the candidate encoder license screen is an engineering risk review, not legal advice or an encoder choice. exact release builds still require locked dependency, runtime, notice, corresponding-source, signature, and notarization review.
- the limited equal-work still-frame review found faint native-size speckling in optimized ImageMagick output at 100% diffusion. the architect confirmed that this sample holds against the approved floor; the review does not assess temporal quality or select an encoder.
- destination file limits can change. the limits quoted in [mvp.md](mvp.md) are a 2026-10-20 research snapshot and need verification before release.
