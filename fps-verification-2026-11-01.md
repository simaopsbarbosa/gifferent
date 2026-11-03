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

light appearance, increased contrast, VoiceOver operation, actual animated GitHub paste, full keyboard navigation, window resizing, and architect final visual approval remain pending. the XCTest acceptance journey for changing FPS/speed, exported timing, and subsequent recording persistence is implemented and compiles, but its local runner did not execute; see the hosted follow-up below.

## performance evidence

see [the frame-rate benchmark report](Benchmarks/frame-rate-presets-2026-11-01.md) and its raw JSON for the contemporaneous 24 fps baseline versus 60 fps source/50 fps export comparison. fixtures cover static UI and motion at 640 by 360 for 10 and 30 seconds. the benchmark measures transform, ImageIO encoding, metadata checks, process time/RSS, captured PNG bytes, and output bytes. it does not measure live capture, PNG creation, UI publication, or complete stop-to-preview latency.

## remaining gates

1. execute the full deterministic UI suite on a Mac/CI environment where the XCTest runner can start. repair any resulting failures before merge.
2. run real 60 fps ScreenCaptureKit acceptance on the reference Mac: sustained throughput and drops, CPU/memory/temp bytes, stop-to-preview latency, cursor/frame exclusion, permissions, hotkeys, moving/resizing or disappearing targets, and cleanup. retain the existing full supported-machine acceptance matrix.
3. review light/dark/accessibility behavior and animated fixture quality with the architect, and verify actual GitHub paste/save. screenshots and unit metadata checks cannot establish these outcomes.
4. the architect accepted the measured encoder cost at the 50 fps default on 2026-11-01. this scoped tradeoff does not establish the under-two-second complete preview target; measure live capture and full preview publication separately.
5. require passing hosted CI and the existing signing/notarization, dependency/source-delivery, clean-Mac, and release-approval gates before distribution.


## hosted acceptance follow-up

initial hosted [run 41264532851](https://github.com/simaopsbarbosa/gifferent/actions/runs/41264532851) passed quality, build, and all unit/integration assertions. one optional research-only ImageMagick integration test was skipped because that installed executable is absent on the runner; ImageMagick is not the shipped encoder, and the test ran locally. all bundled Gifski tests ran in hosted CI.

the hosted UI runner executed and exposed stale selectors from the previous preview refactor: native menus are menu buttons, segmented SwiftUI choices are radio buttons, metadata labels needed separate accessibility containment, and the region drag needed a dedicated canvas target. this change updates those selectors, gives metadata distinct accessible values, exposes the canvas without changing its gesture, and checks the current 280 point proportional viewport instead of the obsolete 232 point bound. native Computer Use confirmed canvas dragging, region recording/frame visibility, preview creation, and separate file-size/duration/dimensions values. the subsequent full local unit/integration run passed 184 tests with zero skips at `.build/ci/test-unit-4xkEKm/Result.xcresult`. hosted UI regression is rerun on the updated branch; its current outcome is tracked on the PR.


hosted follow-up identified further legacy acceptance issues: menu item text is available through the macOS `title` attribute, pointer normalization can choose quality 79 instead of 80, and repeated instant fixture exports can coalesce SwiftUI state and suppress repeated feedback. title assertions now use that attribute, the quality assertion accepts the actual one-step pointer rounding, and a feedback revision makes each completed export present its own notice. the FPS/speed persistence/export journey passed in hosted CI.

XCTest's synthetic region drag still did not select a region on the hosted VM, although native Computer Use performed a real drag and verified region recording/frame visibility successfully. region confirmation/restoration and record-to-export acceptance now use a debug-only region fixture button, analogous to the existing deterministic source and capture fixtures. this selects through the real coordinator and confirms through the normal UI; it does not claim to automate pointer drawing or real screen capture. the control is absent from normal launches and release builds. native pointer drawing and real-Mac capture remain separate acceptance evidence.


## acceptance deferred by the architect

on 2026-11-01, the architect explicitly instructed: “skip acceptance for now”. automated UI acceptance and remaining real-Mac acceptance are deferred. stop acceptance work for this task; retain the existing results and pending gates for a later pass. this does not assert that acceptance passed, mark the feature definition-of-done complete, or authorize merge/release with missing evidence. the feature implementation, local unit/integration tests, benchmark evidence, and PR remain available for review.

## restoration on 2026-11-03

- `f9f2495` removed the fps feature after PR #4 merged. updating the old feature branch to main therefore also removed the controls. restore the approved feature while retaining the trim filmstrip, current selection/branding fixes, and current CI policy.
- `bash Scripts/quality.sh` passes; `git diff --check` passes.
- `bash Scripts/test-unit.sh` passes with 188 tests, zero failures and skips. evidence: `.build/ci/test-unit-byQBmM/Result.xcresult` and `/private/tmp/gifferent-fps-restore-tests-final.log`.
- `bash Scripts/build.sh` succeeds. evidence: `.build/ci/build-lnUh1f/Result.xcresult` and `/private/tmp/gifferent-recording-diagnostic-build.log`.
- the first sandboxed build could not execute SwiftUI macro plugins. an initial unsandboxed verification ran all 188 cases successfully but could not save its result bundle after the disk filled; the separate app build also failed from disk exhaustion. the final runs above occurred after space became available and supersede those incomplete runs.
- the architect reports live capture startup showing `could not start recording; try again`. investigation is ongoing; restored the pre-existing local startup error logger, and requested a fresh attempt with the rebuilt app. unit success does not establish that this live failure is fixed.
- UI and real-Mac acceptance remain deferred. earlier benchmark numbers and native UI observations in this document are historical evidence, not a new acceptance run on the restored branch.

### live recording follow-up

- the architect confirmed that recording starts after rebuilding. a later live preview could not edit, compress, copy, or save.
- the live preview remained ready and its fps menu responded, but changing fps produced `could not update gif; previous preview kept`. the production recording workspace was empty while the preview remained open.
- the full unit suite had launched the app host without `--ui-testing`; its application delegate invoked normal startup, including orphan cleanup in the shared production workspace. that explains the missing recording source files and failed editing/export.
- prevent hosted unit tests from starting the normal runtime and give them a process-specific temporary workspace. add a regression test proving XCTest detection, the isolated path, and idle runtime state after `start()`. retain normal launch and explicit UI-fixture launch behavior.
- the focused isolation check passes: 4 tests, zero failures/skips, `.build/ci/test-unit-qj7Rvi/Result.xcresult`. a fresh real recording is still required; the already-deleted files cannot be restored by this code change.
- after the isolation fix, `bash Scripts/test-unit.sh --no-build` passes all 189 tests with zero failures/skips; evidence: `.build/ci/test-unit-QEBixV/Result.xcresult` and `/private/tmp/gifferent-unit-host-full-suite.log`. `bash Scripts/quality.sh` and `git diff --check` pass. the architect has been asked to verify a new recording after rebuilding; that confirmation is pending.
