# editing and optimization acceptance — 2026-10-25

## scope and numbering

this report tracks the approved [completion checklist](iteration-4-implementation-plan.md). the conversation called it iteration 4; [delivery-plan.md](delivery-plan.md) numbers this fourth development stage as iteration 3, editing and optimization. iteration 4 in that document is hardening and identity. this report does not change either iteration's exit criteria.

## acceptance matrix and path trace

the controls update `RecordingCoordinator.editParameters`; `GIFEditModel` selects the captured PNG frames and transforms their timing. `ImageIOOriginalGIFEncoder` encodes that edited sequence, and the coordinator validates the expected delay schedule and reads back metadata before replacing the current preview. copy and save both read `displayedPreviewGIF`, the same URL shown by preview. while replacement encoding runs, export is disabled; a failed replacement restores the last accepted parameters and GIF.

compression and destination search consume the current validated, edited GIF from the preview state. each search attempt is sampled from that same source, rather than chaining transformations from the previous attempt. the workspace reserves, validates, commits, and removes attempt files. a completed compressed GIF becomes `displayedPreviewGIF`; back-to-original returns to the validated uncompressed edit and removes the compressed file. raw capture frames remain available for subsequent edits until the session closes.

| action or failure | required result | evidence |
| --- | --- | --- |
| trim beginning/end, including the last frame | selected source frames in order; each retained frame keeps its own duration | `OriginalGIFEncoderTests.testEditedGIFPreservesTrimmedFrameContentSpeedAndLoopThroughEncoding`, `testTrimmedIrregularSequenceKeepsLastSelectedFramesOwnDuration` |
| speed 0.5×, 1×, 2× with full, middle, or one-frame selection | exact cumulative centisecond schedule, including the terminal frame | the same encoded-fixture tests; `GIFEditModelTests` invalid-input coverage |
| once/forever loop | matching metadata and GIF application-extension intent | encoded-fixture tests and existing loop-extension parser tests |
| edit → preview → copy/save | the displayed edited GIF is the copied/saved file | `RecordingCoordinatorTests.testNewestEditRequestWinsAndClipboardUsesTheEditedGIF`; `MenuBarSmokeTests.testRecordingActionOpensPreviewAndKeepsExportAfterClose` checks actual exported metadata and byte equality |
| destination search | only approved pairs, selected scale as ceiling, quality ≥90, serial attempts, smallest attempt returned | `GifskiCLICompressorTests` plan, quality-floor, sampler, target and on-disk cleanup tests |
| Discord search | backend, progress, result and target retain Discord | `testDiscordSearchPreservesDestinationAndUsesItsTarget` |
| target missed | best attempted output retained with `reachedTarget == false` | `testSizeSearchKeepsSmallestCandidateUnderTargetAndDeletesOtherAttempts`; UI derives its `best attempt; target not met` copy from this summary |
| invalid output or child failure | output rejected, prior retained attempt removed, original still usable | adapter invalid-output/failure tests, search failure tests, coordinator compression failure tests |
| cancellation, including final cleanup | cancelled result; every attempt removed; original still usable | child-process cancellation, final-discard cancellation, coordinator cancellation tests |
| compressed preview → copy/save → back | valid result exported; back restores byte-identical original edit | `MenuBarSmokeTests.testDestinationCompressionExportsValidatedResultAndReturnsToOriginal` |
| failure/cancel from UI | explicit status and byte-identical original export remains available | `MenuBarSmokeTests.testCompressionFailureAndCancellationKeepOriginalExportUsable` |
| real CLI | pinned Gifski accepts the arguments and preserves canonical timing/loop contracts | `testPinnedRealGifskiCLIWhenPresent`, `testPinnedRealGifskiPreservesCanonical24FPSCentisecondSchedule`, plus the current-path benchmark |

## defects corrected

- edited sequences previously carried only frame-start timestamps. a one-frame selection therefore reverted to the encoder's default interval, ignoring speed; a trim ending inside an irregular capture repeated the preceding interval instead of retaining the last selected frame's own interval. sequences now carry an optional terminal duration, which the edit transform preserves and scales and the encoder quantizes with the rest of the schedule.
- coordinator output validation now compares the entire expected delay schedule, so a valid GIF with incorrect edit timing cannot become the current preview.
- candidate settings previously defaulted back to GitHub when a Discord search constructed an attempt. backend settings, progress and returned settings now retain the requested destination.
- frame sampling now rejects an unsupported total duration before converting its frame-count calculation to `Int`, preventing a trap on extreme metadata.
- cancellation during the final discarded attempt is checked before returning the retained best result; all retained files are removed on that cancellation path.

## deterministic acceptance seam

debug UI tests may inject a valid ImageIO fixture compressor, an explicit failure, or a cancellable operation through `--ui-testing-compression=success`, `failure`, or `cancellable`. this exercises the production coordinator, search, workspace, preview, and export paths without bundling an unreviewed CLI or accessing screen pixels. fixture copy/save adapters retain the actual exported GIF bytes for assertions. normal launches continue to discover only the bundled backend; real Gifski behavior is checked separately with the pinned local executable.

## verification record

verification and benchmark results are recorded here after the complete checks finish. no completion decision is implied by this draft section.

## later gates

the exact bundled Gifski dependency/source/notice audit and normal-build backend packaging remain release blockers recorded in `decisions.md`. live ScreenCaptureKit behavior, permission/hotkeys, frame exclusion, animated paste into GitHub, real macOS brand/accessibility review, signing/notarization, and clean-Mac distribution acceptance remain their owning capture, hardening, and release gates. passing these deterministic edit/optimization checks does not establish those results.
