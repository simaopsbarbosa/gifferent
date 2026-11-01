# frame rate and speed implementation plan

date: 2026-11-01. branch: `codex/gif-fps-presets`, based on refreshed `origin/main` at `1b0982d`.

## requested behavior

- capture targets 60 fps instead of 24 fps. this is a requested target, not a guarantee that every display or workload supplies 60 distinct frames per second.
- place a compact frame-rate menu beside speed and loop in the existing preview control row. replace the speed slider with a native menu; preserve trim and the segmented loop control.
- proposed frame-rate presets: 60, 45, 30, 24, 20, 15, and 10 fps. proposed speed presets: 0.25× through 3× in 0.25× steps. defaults and sampling semantics await the architect's answers recorded in [decisions.md](decisions.md).
- preview, copied GIF, saved GIF, manual compression, and size search must agree with their selected settings and documented timing policy.

## implementation sequence

1. resolve and record the remaining product choices: preset persistence, frame sampling relative to speed, and compression behavior. inspect GIF centisecond timing and viewer compatibility before changing the timing transform. update the scope, edit-model, architecture, performance acceptance, and user instructions with the approved behavior.
2. add tested frame-rate and speed presets and a deterministic sampling transform. preserve frame order, trim boundaries, terminal duration, and loop intent; do not interpolate screen pixels or invent missing capture content. cover sparse and irregular timestamps, short trims, all presets, and combined speed/rate extremes. ensure cumulative centisecond rounding cannot collapse adjacent frames or corrupt total duration.
3. update ScreenCaptureKit's requested interval to 1/60 second. keep bounded transport, workspace quota, cursor setting, cancellation, permission handling, target-loss recovery, and cleanup. expose the requested interval through a testable configuration seam.
4. connect the new selection to coordinator state and the latest-request-wins replacement pipeline. replace the speed slider and add the FPS menu using native SwiftUI controls, accessible names, stable test identifiers, keyboard operation, and the existing compact row. retain export gating, cancellation, and the last usable result after failure.
5. propagate the approved frame-rate policy through manual Gifski compression and bounded size search. retain quality and resolution policy; verify exact duration, frame scheduling, loop, dimensions, byte limits, original recovery, and removal of obsolete files. add real CLI integration coverage for the new timing cases.
6. extend deterministic UI acceptance to select FPS and speed, combine trim/loop, copy/save and inspect the result, recover from failure/cancellation, return from compression, and fit the compact initial/minimum window. review the actual native UI in light/dark appearance and check keyboard and accessibility behavior.
7. benchmark 24 fps baseline and 60 fps capture/export on the same fixtures and machine, including representative static UI and motion and short/long recordings. record machine/OS/power mode, fixture hashes, median/p90 time, peak memory, workspace bytes, output bytes, dropped frames, and animated visual review. distinguish fixture encoder measurements from live capture and stop-to-preview measurements.
8. run the full definition-of-done checks, commit reviewable milestones, publish the branch, and open a feature-specific pull request with behavior, evidence, privacy/permission impact, documentation, and any remaining gates. monitor hosted CI and fix regressions. do not merge, publish a release, or call the feature complete with missing required evidence.

## acceptance scenarios

- a new recording requests 60 fps, opens the expected default selections, and exports a valid animated GIF whose duration and loop match the preview.
- changing FPS changes temporal sampling without changing intended playback duration; changing speed changes duration according to the approved sampling policy. trimming preserves source boundaries and the final interval.
- all preset combinations, including 0.25× and 3×, produce positive representable GIF delays and correct duration; sparse capture does not imply fabricated visual detail.
- rapid changes publish only the newest valid result. copy/save remain unavailable while stale; cancellation, encoding failure, closing, target loss, and workspace exhaustion follow existing recovery and cleanup rules.
- compression follows the approved FPS policy, size search remains bounded, and returning to the original restores the expected controls and file.
- controls fit the current compact preview, have accessible names and values, and work by keyboard. copied and saved bytes match the validated current GIF.

## required evidence

run `bash Scripts/ci-local.sh`, which checks the pinned toolchain, Markdown links, brand assets, bundled notices, benchmark harness, formatting, strict lint, build, unit/integration tests, and deterministic UI acceptance. run `git diff --check` as well. record exact commands and result paths in a feature verification report, including hosted CI results.

real-Mac checks include sustained capture and resources at 60 fps, cursor/frame exclusion, permission recovery, hotkeys, target movement/loss, actual animated GitHub paste, save, visual fit, keyboard use, and VoiceOver. existing release signing/notarization and clean-Mac gates remain applicable. a fixture test or compilation alone cannot establish these results.
