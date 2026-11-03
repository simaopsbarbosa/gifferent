# preview UI refactor verification

date: 2026-11-01. branch: `codex/refactor/preview-ui`.

## status

the implementation, local build, unit/integration suite, formatting, lint, documentation, bundled-license checks, and quality-default benchmark pass. the feature is **not definition-of-done complete**: automated UI acceptance is blocked by local signing policy, final native visual/accessibility acceptance is unverified, and hosted CI has not run for this branch. this report records evidence and blockers; it does not waive any requirement in [definition-of-done.md](definition-of-done.md).

the architect explicitly approved creating a local commit with these acceptance gates pending on 2026-11-01. this authorizes the local commit, not merge, release, or a claim that the remaining checks passed.

## behavior and scope

- compact, resizable native preview: 560 point initial width, measured initial content height, 280 point preview height, proportional image scaling, equal 12 point top/side margins, and increased metadata padding. scrolling remains available on a short screen or after manual shrinking. GIF updates preserve the user's window frame.
- trim, speed, segmented loop, resolution presets, and quality remain grouped below the preview. quality defaults to 100 without automatically compressing the initial GIF. resolution changes compress immediately; pointer scrubbing waits for release followed by one idle second. keyboard adjustments use the same idle delay.
- `compress for` is an action menu listing Discord (20 MB max) and GitHub (10 MB max), without a selected platform in its label. no third-party logos are bundled. the approved bounded search and quality floor remain intact.
- updates show an in-preview spinner. copy/save are unavailable while output is stale; close remains available. previous output and metadata remain usable until a replacement is validated. back cancels pending work and restores the original; failure/cancellation retains the previous exported result.
- copy/save feedback and the unavailable-resolution explanation use floating, timed native-material notices. routine updates do not show a completion message or target summary. the back arrow sits beside copy; copy/save show their keyboard shortcuts. save uses a native sheet above the active preview.

capture content stays local. no dependencies, external transfers, telemetry, optional sound, or brand motion were introduced. Gifski's existing notices/source-delivery/signing/notarization release gates remain applicable.

## local checks

| command | result |
| --- | --- |
| `bash Scripts/check-toolchain.sh` | passed: Xcode 27.1, build 27A9275; the previously approved pin is now consistent across CI, script, README, and architecture. |
| `python3 Scripts/check-docs.py` | passed: local Markdown links resolve. |
| `python3 Scripts/check-brand-assets.py` | passed: approved light/dark menu-bar resources. |
| `python3 Scripts/check-gifski-notices.py` | passed: pinned binary, dependency graph, and notices. |
| `python3 -m unittest discover -s Benchmarks -p 'test_encoder_benchmark.py' -v` | passed: benchmark harness. |
| `bash Scripts/format-check.sh` | passed: all 44 Swift files. |
| `bash Scripts/lint.sh` | passed: strict recursive lint. |
| `CI=true bash Scripts/build.sh` | passed: macOS Debug build with signing disabled, as in hosted CI. |
| `bash Scripts/test-unit.sh` | passed: 174 tests, zero failures, zero skips; includes real Gifski integration and compilation of the UI acceptance target. |
| `bash Scripts/test-ui.sh` | blocked: runner killed before establishing its XCTest connection; no UI cases executed. |
| `git diff --check` | passed. |

local build evidence: `.build/ci/build-cpXrMe/Result.xcresult`. unit evidence: `.build/ci/test-unit-xruATp/Result.xcresult`. UI startup evidence: `.build/ci/test-ui-8SCUH1/Result.xcresult`. build/test scripts retain complete local logs and result bundles under `.build/ci/`; generated binaries and result bundles are intentionally ignored by Git.

the unit run emits an existing runtime priority-inversion diagnostic in `OriginalGIFEncoderTests.testCancellationRemovesPartialGIF`. Xcode also emits its non-actionable AppIntents metadata-extraction notice. no Swift compiler warnings were reported after moving UI test teardown onto its async actor context.

## regression evidence

unit coverage includes one-second debounce publication, waiting through a stationary pointer hold, unchanged-value scrubbing, cancelling pending quality work on back, in-place recompression, retained output/metadata/export state after failure or cancellation, original recovery, combined cache/session quotas, real encoded timing/loop metadata, and export cleanup. the two real-Gifski tests now locate the repository's bundled executable correctly instead of skipping.

UI acceptance assertions cover compact initial fit, copy notice expiry without height changes, window position across edits, segmented loop selection, action-menu choices, temporary unavailable-resolution feedback, manual quality/resolution compression, keyboard export, busy action availability, cancellation, and original recovery. these assertions compile but have not executed successfully on this Mac.

## quality-default benchmark

the [reproducible comparison](../Benchmarks/compare_quality_defaults.py) compares quality 90 with 100 on the same two 10-second, 640 by 360, 24 fps synthetic fixtures used in the published quality sweep. regenerated manifest and frame-set hashes must match that baseline. each setting has one cold and seven warm runs. p90 uses nearest rank, which is the largest of seven warm samples; these timings are indicative, not a latency guarantee.

machine: Mac14,2; macOS 27.0.1; Xcode 27.1/27A9275; battery power, 61% at the start. memory is command peak RSS from `/usr/bin/time -l`, not total app memory. timings include launching the encoder. compare the contemporaneous quality-90 and quality-100 samples rather than assuming equal power conditions to the historical run.

| fixture | quality | warm median / p90 seconds | median / p90 peak RSS, MiB | output bytes |
| --- | ---: | ---: | ---: | ---: |
| mostly-static-ui | 90 | 0.532 / 0.601 | 78.8 / 85.3 | 15,311 |
| mostly-static-ui | 100 | 0.531 / 0.542 | 81.5 / 85.2 | 15,365 |
| high-motion-gradient-cursor | 90 | 0.975 / 1.051 | 81.0 / 88.0 | 5,792,443 |
| high-motion-gradient-cursor | 100 | 0.928 / 0.959 | 80.9 / 89.8 | 14,562,564 |

every sample has valid dimensions, 240 frames, exact 10-second duration, and infinite-loop metadata. every output is byte-identical to its corresponding previously reviewed quality-90 or quality-100 animation, establishing unchanged animation content for these fixtures. the new default can produce substantially larger motion files; no general speed improvement is claimed. original preview creation does not invoke this compression pass.

the default bounded destination plan now tries 12 candidates instead of four because quality starts at 100 and steps through 95 and 90 for each approved pair. unit tests verify this bound. this benchmark measures the encoder stage, not complete destination-search latency, screen capture, hotkey response, stop-to-preview latency, native UI responsiveness, or memory for the whole app.

raw per-sample timings, RSS, hashes, and metadata: [quality-default results](../Benchmarks/results/ui-refactor-quality-default-2026-11-01.json).

reproduce with a fresh directory:

```sh
quality_run="$(mktemp -d /private/tmp/gifferent-quality-XXXXXX)"
python3 Benchmarks/generate_fixture.py --output "$quality_run/static" --profile mostly-static-ui --frames 240
python3 Benchmarks/generate_fixture.py --output "$quality_run/motion" --profile high-motion-gradient-cursor --frames 240
python3 Benchmarks/compare_quality_defaults.py --static-fixture "$quality_run/static" --motion-fixture "$quality_run/motion" --output "$quality_run/results"
```

## gates remaining

1. run the full UI suite with a valid Apple Development signing identity and permitted Xcode automation. AMFI reports that the ad-hoc runner is invalid; `security find-identity -v -p codesigning` reports zero valid identities. native Computer Use inspection also timed out. no security setting was weakened to bypass these failures.
2. verify native appearance in light/dark mode, increased contrast, reduced motion, keyboard navigation, VoiceOver feedback, actual save-sheet ordering/cancellation, wide/tall GIF layout, content fit, and frame preservation on a real Mac.
3. run the updated pinned GitHub Actions jobs after the branch is published. no push or hosted-CI run was requested in this task.
4. retain the existing release acceptance gates for live Screen Recording permission, global shortcuts, multiple displays/windows, overlay exclusion, animated GitHub paste, complete latency/resource measurements, and signed/notarized distribution. controlled fixture tests do not establish these outcomes.

do not merge or describe the feature as definition-of-done complete until the applicable gates pass or the architect explicitly approves a recorded exception.
