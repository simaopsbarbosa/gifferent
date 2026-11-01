# frame rate and speed verification

date: 2026-11-01. branch: `codex/gif-fps-presets`, based on `origin/main` at `1b0982d`.

## status and behavior

implementation and controlled export tests are present. definition-of-done completion remains blocked on automated UI acceptance, live capture/resource acceptance, final visual/accessibility review, and hosted CI. this report does not waive those gates.

- ScreenCaptureKit requests 60 fps. output defaults to 50 fps at 1×, with FPS presets 50/45/30/24/20/15/10 and speed presets 0.25×–3× in 0.25× steps. native SwiftUI menus share the existing row with segmented loop selection.
- FPS applies to final playback after speed. cumulative centisecond boundaries preserve rounded duration; sparse source frames are held rather than interpolated. very short clips retain one 20 ms frame. the 50 fps ceiling avoids browser clamping of 10 ms GIF delays.
- validated FPS/speed selections persist across recordings and launches. invalid stored settings fall back to 50 fps/1×; trim and loop reset for each recording. failures restore the previously validated selections.
- manual compression uses selected FPS. automatic search keeps the approved original/24, 75%/24, 50%/24, and original/18 pairs, constrained by selected FPS and resolution. below 18 fps there are no approved automatic candidates; manual compression remains available. help and floating feedback explain unavailable search. back restores the original selected ceiling.
- latest-request publication, copy/save gating, cancellation, permission recovery, target-loss handling, cursor preference, bounded transport, session quota, and cleanup remain in place. capture pixels remain local; no new dependencies, permissions, transfers, or telemetry were added.

## local checks

| command | result |
| --- | --- |
| `bash Scripts/check-toolchain.sh` | passed through the local CI entry point: Xcode 27.1 / 27A9275. |
| `python3 Scripts/check-docs.py` | passed: local Markdown links resolve. |
| `python3 Scripts/check-brand-assets.py` | passed through local CI. |
| `python3 Scripts/check-gifski-notices.py` | passed through local CI. |
| `python3 -m unittest discover -s Benchmarks -p 'test_encoder_benchmark.py' -v` | passed through local CI. |
| `bash Scripts/format-check.sh` | passed: 44 Swift source/test files. |
| `bash Scripts/lint.sh` | passed: strict lint. |
| `CI=true bash Scripts/build.sh` | passed through local CI: macOS 14 deployment target. |
| `bash Scripts/test-unit.sh` | passed: 184 tests, no failures or skips; includes real pinned Gifski integration and compilation of the UI target. final rerun after the single-frame fallback and unavailable-search feedback updates also passed. |
| `bash Scripts/test-ui.sh` | blocked: UI runner was killed before establishing its XCTest connection; no UI cases executed. |
| `git diff --check` | passed. |

`bash Scripts/ci-local.sh` passed the checks through unit/integration testing, then failed at UI-runner startup. evidence: `.build/ci/build-QZS3ad/Result.xcresult`, `.build/ci/test-unit-aEfeto/Result.xcresult`, and `.build/ci/test-ui-7JHalx/Result.xcresult`. subsequent unit evidence: `.build/ci/test-unit-fKFO11/Result.xcresult`; final unit evidence: `.build/ci/test-unit-jPzio6/Result.xcresult`. `security find-identity -v -p codesigning` reported zero valid identities. the XCTest result reports an early unexpected exit with signal kill before connection; a valid test signing identity and functional UI-runner environment remain needed. no security protection was weakened.

tests cover all 84 FPS/speed combinations on 60 fps source frames, exact rounded duration, browser-compatible positive delays, source-frame ordering/content, trim boundaries, sparse frames, very short clips, loop modes, rejected inputs, preference validation and restoration, capture interval, newest-request publication, exports, cleanup, and search ceilings. real Gifski tests exercise every export FPS with both loop modes and validate dimensions, total duration, delays, and temporary-directory cleanup.

## native inspection

Computer Use inspected the actual built SwiftUI preview using deterministic synthetic frames, without requesting live screen recording permission:

- dark native preview fits the initial 560 point window: trim, speed/FPS menus, segmented loop, compression, metadata, and export actions remain visible. all FPS presets and all twelve speed choices are exposed through native popup controls with accessible names and values.
- selecting 10 fps disables automatic size search. selecting 0.25× changes the fixture duration from 0.13 to 0.50 seconds; native menus use the user's locale (`0,25×` on this Mac). keyboard Home/End/Return selects speed presets, including 3×. deterministic UI tests explicitly use English/US formatting for stable numeric menu selectors.
- with 10 fps, 0.25×, and loop once, `⌘C` and `⌘S` complete. the synthetic copied/saved files were byte-identical, 16 by 16, three frames, delays `[20, 20, 10]` centiseconds, total 0.50 seconds, and no loop extension.
- the next fixture recording restores 10 fps/0.25× while resetting loop to forever. manual 75% compression through bundled Gifski succeeds at 12 by 12 with the same duration; back restores the 16 by 16 preview and selected FPS/speed.
- the fixture app was closed after the checks, cleaning its session media. these checks exercise test export adapters; they do not prove real clipboard compatibility, a native save sheet, or live ScreenCaptureKit behavior.

light appearance, increased contrast, VoiceOver operation, actual animated GitHub paste, full keyboard navigation, window resizing, and architect final visual approval remain pending. the XCTest acceptance journey for changing FPS/speed, exported timing, and subsequent recording persistence is implemented and compiles, but its runner did not execute.

## performance evidence

see [the frame-rate benchmark report](Benchmarks/frame-rate-presets-2026-11-01.md) and its raw JSON for the contemporaneous 24 fps baseline versus 60 fps source/50 fps export comparison. fixtures cover static UI and motion at 640 by 360 for 10 and 30 seconds. the benchmark measures transform, ImageIO encoding, metadata checks, process time/RSS, captured PNG bytes, and output bytes. it does not measure live capture, PNG creation, UI publication, or complete stop-to-preview latency.

## remaining gates

1. execute the full deterministic UI suite on a Mac/CI environment where the XCTest runner can start. repair any resulting failures before merge.
2. run real 60 fps ScreenCaptureKit acceptance on the reference Mac: sustained throughput and drops, CPU/memory/temp bytes, stop-to-preview latency, cursor/frame exclusion, permissions, hotkeys, moving/resizing or disappearing targets, and cleanup. retain the existing full supported-machine acceptance matrix.
3. review light/dark/accessibility behavior and animated fixture quality with the architect, and verify actual GitHub paste/save. screenshots and unit metadata checks cannot establish these outcomes.
4. the architect accepted the measured encoder cost at the 50 fps default on 2026-11-01. this scoped tradeoff does not establish the under-two-second complete preview target; measure live capture and full preview publication separately.
5. require passing hosted CI and the existing signing/notarization, dependency/source-delivery, clean-Mac, and release-approval gates before distribution.
