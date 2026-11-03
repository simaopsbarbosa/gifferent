# thumbnail trim control plan

## status and intent

documentation plan, 2026-11-01; no product code is changed by this document. this is a focused refinement of iteration 3 editing, subject to the existing [delivery gates](delivery-plan.md) and [definition of done](definition-of-done.md).

replace the thin trim track and circular handles with the familiar macOS video-trimming treatment: a strip of recording thumbnails, a yellow selected-range outline, and independently draggable yellow handles at both ends. keep excluded footage visible but dimmed so the selection has context. the attached reference establishes this control direction; its surrounding layout, playback button, dimensions, frame-rate control, and conversion flow are not requirements for gifferent.

the architect confirmed that trimming must stay inline. prefer Apple's native control if public APIs can satisfy that interaction; otherwise use SwiftUI. a separate native trim/cancel step is not the chosen experience. final visual approval remains with the architect.

## current behavior and integration seams

- [GIFPreviewViews.swift](../Sources/App/GIFPreviewViews.swift) contains `GIFEditControls`, `GIFTimelineControl`, and `GIFTimelineHandle`. the track currently spaces handles by frame index, has no thumbnails, and sends each handle movement to `RecordingCoordinator.updateTrim`.
- the main preview uses an animated `NSImageView`, not an `AVPlayer`. the retained editing source is a `CapturedPNGSequence`, not a movie asset.
- [RecordingCoordinator.swift](../Sources/Recording/RecordingCoordinator.swift) cancels superseded edit requests, validates replacement GIFs, retains the previous preview during work, and disables export until the newest edit is ready. failed edits restore the last validated parameters.
- [editing-model.md](editing-model.md) defines the authoritative range: inclusive start, exclusive end, at least one source frame, original ordering, timestamp-based timing, and explicit terminal-frame duration. preserve that contract, speed, loop, compression restrictions, original recovery, and cleanup.

inspect the current working tree again before implementation; this plan does not approve or replace other work in progress.

## native API feasibility and choice

Apple documents QuickTime-style trimming in macOS `AVPlayerView`. availability depends on the player and media; its public entry point exposes completion through trim/cancel. native trim bounds live on the player item and do not rewrite its asset. see [Apple's macOS trimming guide](https://developer.apple.com/documentation/avkit/implementing-trimming-in-a-macos-player), [`canBeginTrimming`](https://developer.apple.com/documentation/avkit/avplayerview/canbegintrimming), and [`beginTrimming(completionHandler:)`](https://developer.apple.com/documentation/avkit/avplayerview/begintrimming(completionhandler:)).

this establishes a native candidate, not a standalone filmstrip API or a guarantee that the screenshot uses it. gifferent's frame-based source also requires an asset strategy before this player can be used.

| approach | investigation | selection gate |
| --- | --- | --- |
| native `AVPlayerView` in a narrow SwiftUI bridge | verify on macOS 14 and the current supported OS whether public APIs support the required inline interaction, range observation, keyboard use, source timing, resizing, and recovery. identify any temporary movie requirement and measure its cost. | use only if it fits without private subview access, hiding system confirmation buttons, blocking first preview, or changing export semantics. document why this small bridge provides a capability SwiftUI cannot supply directly. |
| SwiftUI filmstrip over retained PNG frames | reuse `GIFEditModel` and the coordinator; decode only bounded thumbnails from existing local frames. | use when the native candidate cannot meet the approved inline flow or has unacceptable measured cost. this is the recommended fallback, not permission to redesign the rest of the preview. |

timebox the native check to a feasibility experiment; record its result before production implementation. do not add a permanent video pipeline merely to obtain yellow handles. any internal temporary asset must stay private, fit the session quota, preserve exact source timing, and be cleaned up; video export remains outside scope.

## interaction proposal for review before implementation

the requested visual direction and inline flow are confirmed. the following details are recommendations until the architect reviews them; record answers in [decisions.md](decisions.md) before coding dependent behavior.

1. keep a compact, full-width filmstrip in the current trim position below the GIF. show representative still thumbnails across the entire original recording. yellow describes trim selection only; it does not change the approved orange brand mark. retain clear handle grips and focus indicators so color is not the only cue.
2. make thumbnail positions proportional to source time, using actual timestamps and the terminal interval rather than assuming every frame arrived at 24 fps. snap handle choices to source-frame boundaries. the right boundary represents the exclusive end; boundary inspection shows the last included frame. handle geometry must permit a one-frame range without crossing or making either handle unreachable.
3. recommend live local range feedback while dragging, with a temporary still of the active boundary frame in the main viewport. this still is source inspection, not a newly encoded output. commit a replacement GIF on pointer release or keyboard/accessibility adjustment, rather than encoding on every pointer movement. keep export unavailable while a draft differs from the validated output. on cancellation restore the pre-gesture range; on encoding failure restore the last validated range and preview. this proposal changes update cadence and needs explicit approval.
4. recommend limiting the first slice to thumbnails and handle-based boundary inspection. clicking or dragging the strip interior to scrub, a playhead, and a new play/pause button are separate optional behaviors. the screenshot alone does not approve them. if requested, specify source-versus-output timing, speed/loop interaction, focus, and returning to animated GIF playback before implementation.
5. preserve the existing compressed-result and busy-state restrictions. close/discard cancels outstanding thumbnail and inspection work as well as replacement encoding. moving a handle must not launch compression or mutate the source sequence.

review questions: approve the boundary still and release-to-encode cadence, or retain the current update-on-movement behavior? are strip thumbnails and handle inspection sufficient, or is independent interior scrubbing required? the recommendation is boundary inspection with release-to-encode, leaving independent scrubbing for a separate slice. the tradeoff is less repeated encoding and a smaller interaction surface, with no free playhead in this first change.

## engineering sequence

one integration owner is responsible for this complete slice. respect outstanding iteration gates; this plan does not declare earlier acceptance complete.

1. **settle interaction and baseline.** obtain the two interaction answers above; capture final intended behavior and scenarios. record the current track's latency, encoding requests per drag, CPU, peak memory, and temporary bytes on the same fixtures and Mac used for candidate measurements.
2. **resolve the native candidate.** run the feasibility experiment with a controlled source; record supported OS results, exact time-to-frame mapping, asset creation costs, accessibility, and the inline-flow verdict. choose the implementation using the gates above.
3. **implement source-time geometry.** isolate only the mapping needed for this control. use frame-start timestamps plus a terminal boundary. define deterministic nearest-boundary snapping and tie-breaking, clamping, one-frame behavior, and display-time labels. range changes continue through `GIFEditParameters`; no second edit model.
4. **load a bounded filmstrip.** choose sample count from visible width and a documented hard cap; downsample during decoding rather than retaining full-size source images. perform decoding off the main actor with bounded concurrency. key results by session, sample index, and thumbnail size; cancel obsolete generations on resize, source replacement, and close. use bounded in-memory caching by default, without a new persistent thumbnail directory. fill loading slots without blocking first usable GIF preview. a thumbnail failure keeps trim usable and shows a restrained unavailable slot; it must not discard the recording.
5. **integrate approved interaction.** add separate draft/validated state only if release-to-encode is approved. prevent stale thumbnail, inspection, or encode results from publishing after a newer request or close. retain existing export validation and failure rollback. if native playback is selected, map its time bounds back to original frame indices and still export through the existing GIF pipeline.
6. **verify and review.** run the matrix below, compare measurements, collect real-Mac visual/accessibility evidence, and update the source-of-truth documents with the final implemented behavior. do not claim native equivalence or a performance improvement without evidence.

## acceptance and evidence

| scenario | required evidence |
| --- | --- |
| initial preview | full source selected; thumbnails depict beginning, middle, and end in order; no unintended edit or compression; first usable GIF does not wait for the strip. |
| both handles | each end moves independently; yellow border follows the range; excluded frames dim; no crossed, empty, or out-of-bounds selection. resizing preserves the selected frames. |
| frame accuracy | start-only, end-only, both-end, full-range, and one-frame trims agree with copied/saved GIF frame identity, order, delays, total duration, speed, and loop metadata. include irregular timestamps and explicit terminal intervals. |
| inspection, if approved | dragging shows the selected boundary frame without full-GIF encoding per movement; release submits the final range; cancelling restores the prior range. stale inspection frames cannot replace a newer preview. |
| asynchronous recovery | rapid drags, thumbnail failure, encode failure, close/discard, and low disk conditions retain the last usable result and clean pending work. exports cannot publish stale bytes. compressed-result/back behavior is unchanged. |
| keyboard and VoiceOver | both handles remain independently discoverable, focused, named, and adjustable by one source frame; values expose frame position and time. overlapping handles and one-frame clips remain usable without a pointer or hover. preserve `trim-start-handle` and `trim-end-handle` identifiers or provide a documented equivalent for a native bridge. |
| appearance and sizing | architect reviews yellow handles, grips, dimming, and thumbnails at normal/minimum window sizes, portrait/landscape clips, 1×/2× display scale, light/dark, increased contrast, and reduced motion. no unrelated layout change. |
| resource bounds and privacy | long/high-resolution clips cannot create unbounded decoding or caching. no new permission, network request, or persistent captured-content cache. close and crash cleanup leave no new media behind. |

use unit tests for time/position mapping and frame bounds; integration tests for bounded loading, cancellation, newest-result publication, and exported bytes; deterministic XCTest UI tests for pointer, keyboard, VoiceOver-facing values, and recovery journeys. avoid image-only assertions for frame correctness.

benchmark current and proposed paths with identical static-UI, scrolling, and high-motion fixtures, including one frame, ten seconds, thirty seconds, irregular timestamps, and a longer quota-constrained source. record machine, OS, power mode, fixture checksums, sample/cache/concurrency caps, median and p90 first-thumbnail and input-to-feedback latency, release-to-validated-GIF latency, CPU, peak memory, temporary bytes, encoding count, and final GIF bytes. compare source/output visual quality and exact frame timing. propose numeric UI latency/resource budgets from the baseline and obtain an architect decision on any material regression; no new threshold is asserted here.

## checks and documentation handoff

for this documentation-only change, run `python3 Scripts/check-docs.py` and `git diff --check`. product builds and tests are deferred to implementation because no executable behavior changes here.

after implementation, run `bash Scripts/ci-local.sh`, which includes the pinned-toolchain check, documentation/brand/notice checks, benchmark harness tests, format check, strict lint, build, unit/integration tests, and UI acceptance. record exact commands and results; a skipped or unavailable UI run is pending evidence, not a pass. validate the native candidate and final control on macOS 14 and a current supported macOS release, including a real-Mac visual and keyboard/VoiceOver pass.

update [mvp.md](mvp.md), [architecture.md](architecture.md), [editing-model.md](editing-model.md), [decisions.md](decisions.md), and [brand.md](brand.md) where approved details affect them. link benchmark evidence from [Benchmarks/README.md](../Benchmarks/README.md). keep current product specifications unchanged until the proposed details are approved. merge and release remain subject to all existing gates.
