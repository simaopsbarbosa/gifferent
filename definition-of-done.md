# definition of done

a feature is complete only when all applicable checks below have evidence. an exception is a recorded product decision, not a silent skip.

## behavior

- the implemented behavior matches [mvp.md](mvp.md), the architect's latest answers, macOS conventions, and the project's file and code conventions.
- success, cancellation, permission denial, disappeared capture targets, encoder failures, disk errors, and cleanup have defined behavior where relevant.
- app copy, accessibility text, documentation, and comments follow the lowercase voice rules in [vision.md](vision.md).
- visible branded surfaces use the architect-approved artwork and usage rules from [brand.md](brand.md). visual review checks menu bar size, light/dark appearance, and reduced motion.

## verification

- unit tests cover the changed logic: geometry, timing, state transitions, size targeting, setting persistence, and error mapping as relevant.
- integration tests cover the seams touched by the change, including ScreenCaptureKit adapters, frame processing, command-line encoding, metadata, clipboard, and disk export using controlled fixtures or suitable system integration. real-Mac animated clipboard compatibility is tested in GitHub for the first release.
- automated acceptance tests exercise each affected user journey through the macOS UI with XCTest UI tests. provide stable launch arguments and deterministic test fixtures so CI does not depend on an uncontrolled desktop recording for every pull request. a real-Mac acceptance pass checks system permission, global hotkeys, multi-display selection, window movement, animated clipboard paste into GitHub, sound, and visual feel before release.
- every existing feature remains covered by its unit, integration, and acceptance tests; run the full suite before merge. a regression gets a focused test.
- build succeeds on the supported deployment target. no new compiler warnings, force unwraps in fallible capture paths, unhandled task failures, or persistent temporary media.

## performance and quality

- for capture, encoding, compression, or UI latency changes, run repeatable benchmarks with the same source fixtures, machine, OS, and power mode. record median and high-percentile time, peak memory, output bytes, and visual comparison. compare at least two credible approaches before committing to an important encoder or pipeline choice.
- measure hotkey-to-ready, stop-to-preview, sustained 24 fps capture, CPU and memory during normal use, and compression time for short and long fixtures. meet the agreed thresholds or document the architect-approved tradeoff.
- validate GIF duration, frame ordering, loop behavior, final dimensions, size, and animation in the destinations used for acceptance.

## tooling and continuous integration

- run `xcrun swift-format format --in-place --recursive .` and `xcrun swift-format lint --strict --recursive .` on Swift sources, or the equivalent commands fixed in repository scripts once the Xcode project exists. CI runs the formatter and fails if it changes tracked files. formatting and linting are required checks.
- run the full `xcodebuild` build and test plans on a macOS GitHub Actions runner. separate fast unit/integration checks from UI acceptance checks if it makes failures easier to diagnose; both are required to merge. upload `.xcresult` and relevant logs on failure.
- pin Xcode and runner versions deliberately. verify bundled CLI checksums, licenses, architecture support, code signing, and notarization in release automation. do not put signing credentials in pull-request workflows.
- create the actual GitHub Actions workflows when the Xcode project, schemes, test plans, and scripts exist; a documentation-only workflow now would falsely imply the app is tested.

## documentation and review

- update user-facing instructions and the relevant design/architecture decisions in the same change. keep the README short and operational when it is introduced.
- the pull request states what changed, why, tests run, benchmarks run, known limits, and any real-Mac checks pending. the architect reviews new behavior and visual choices.
