# editing and optimization completion plan

## goal

numbering correction: the conversation called this work iteration 4. the delivery plan numbers editing and optimization as iteration 3, followed by iteration 4 hardening and identity. this checklist retains its filename for existing links and covers the editing and optimization scope approved by the architect.

complete the editing and optimization iteration in [delivery-plan.md](delivery-plan.md): the GIF shown in preview must agree with exported/copyable output, and destination compression must preserve the required media contract while returning an honest size result.

this is an execution checklist, not a change to approved product behavior. keep the decisions in [decisions.md](decisions.md) authoritative: trim handles, 0.5×–2× speed in 0.1× steps, once/forever loops, Gifski quality 1–100 (default 90), the approved automatic search candidate pairs, and a quality floor of 90.

## observed baseline

- `GIFEditModel` and unit tests cover trim ranges, speed-adjusted timestamps, loop mode, and invalid timing.
- preview UI acceptance exercises the trim handles, speed slider, loop controls, copy, and save. Its current assertions do not establish that a changed trim selection is applied to the actual encoded/exported GIF.
- Gifski argument, timing, candidate-planning, size-search, cancellation, failure, and workspace cleanup tests already exist. Coordinator tests cover keeping the original and presenting a search result.
- compression UI acceptance currently verifies destination labels, target sizes, quality default, and the unavailable-backend state. It does not traverse a successful end-to-end compression journey with a real encoder.
- benchmark and visual-review artifacts exist, including quality and scale/rate studies. The review page for the initial scale/rate matrix explicitly says it does not approve candidates; the later approved candidate set in `decisions.md` is narrower. treat benchmark artifacts as evidence, not as proof that current implementation passes every approved candidate.
- the working tree has local changes. before implementation, inspect and preserve them; do not reset or overwrite them.

## work packages

### 1. lock the acceptance matrix against current behavior

trace the preview state, edit model, encoder input, clipboard item, save path, and compressed-output path. map each path to its unit/integration/UI coverage and list actual gaps before changing code. confirm the preview and export use the same edit parameters and identify whether size search consumes the edited sequence or the original capture.

**acceptance:** a short matrix names each user action, expected GIF metadata/content, existing test, and missing test. any behavior not settled by the source documents is recorded in `decisions.md` and held for the architect; do not infer new product behavior.

### 2. close edit-to-output consistency gaps

add or extend deterministic fixture tests proving that selected trim bounds, playback speed, and once/forever mode survive through GIF encoding and the copy/save output paths. cover minimum/maximum supported speed and boundary trims, including the last frame. compare duration, frame count, loop metadata, dimensions, and representative frame ordering/content against expected values. fix only mismatches found in the trace.

**acceptance:** every edit is reflected identically in preview, copied GIF, and saved GIF; exact GIF timing follows the existing centisecond contract; failures leave the original preview usable and clean temporary files.

### 3. finish optimizer contract and failure coverage

audit the implementation against the approved search rules: only eligible scale/frame-rate pairs at or below the selected maximum; quality steps down in five-point increments and never below 90; serial candidates; smallest under-target result; otherwise best attempt with a clear miss result; original remains usable. add focused tests for any uncovered branches, especially no candidate under target, invalid output metadata, process failure, cancellation between candidates, and cleanup of superseded/failed outputs.

confirm target values and displayed caveats match the approved 90% goals (9 MB GitHub, 18 MB Discord non-Nitro) and current published caps. cap freshness is rechecked at release as already required by `decisions.md`.

**acceptance:** tests assert the returned candidate, size/target status, duration, dimensions, loop mode, output validity, and on-disk cleanup for success, miss, error, and cancellation.

### 4. prove the complete UI journey

extend deterministic XCTest UI coverage to change trim bounds, speed, and loop mode, then verify the resulting exported fixture metadata/content rather than checking controls alone. add a successful compression journey through the coordinator/UI using a controlled executable or injected backend, plus a failure/cancellation journey that confirms original preview recovery and clear status. keep live Screen Recording permission out of CI.

**acceptance:** automated UI/integration evidence covers edit → preview → copy/save and destination compression → result/back-to-original, including failure and cancellation. any live encoder test must use a pinned, identified binary and remain separate from shared-runner screen capture.

### 5. complete benchmark and visual evidence for approved search points

use the established synthetic fixtures and the reference Mac/environment protocol in `Benchmarks/README.md`. measure the exact approved search candidate pairs and representative full-path behavior on identical inputs. record tool/build identity, fixture hashes, OS/Xcode/Mac/power mode, median and p90 time where sample count supports it, peak memory, temporary disk use, output bytes, and GIF metadata validity. retain reviewable animated samples for the approved quality floor; include text, cursor, gradients, and motion at native scale, with 2× inspection where it helps diagnose artifacts.

the existing size-search quality-floor review includes points later excluded by the architect and documents its own limits. reuse its provenance where applicable, but report only the approved candidate set as implementation evidence. do not claim an unmeasured candidate or full-animation quality result.

**acceptance:** a concise report links reproducible commands/data and representative reviews, distinguishes measured evidence from visual judgment, and shows the selected search behavior meets the size goal when possible or returns the best attempt honestly.

### 6. run iteration exit checks and record the result

run the repository format, strict lint, build, unit/integration, and deterministic UI acceptance scripts after the code and docs are complete. review `git diff --check`, inspect generated outputs, and update the relevant documentation and benchmark index. report exact commands/results, remaining hardware-dependent checks, and any blocked release concerns separately from iteration 3 completion.

**acceptance:** all required automated checks for this slice pass; `delivery-plan.md`'s iteration 3 exit evidence is linked to concrete tests and benchmark artifacts. if a required test or measurement cannot be completed, keep iteration 3 open and state the specific blocker.

## dependency order

1. acceptance matrix and path trace.
2. edit-to-output fixes and optimizer contract gaps (can proceed in parallel only after interfaces/ownership are clear).
3. UI journey coverage against the settled behavior.
4. approved-candidate benchmark and visual review.
5. full checks, documentation update, and iteration exit decision.

## iteration 3 exit decision

mark the iteration complete only after the edit/export contract, compression success/miss/failure/cancellation behavior, fixture/UI acceptance, and approved-candidate benchmark evidence above are satisfied. Gifski distribution licensing, real-Mac capture/paste, signing, and notarization remain later hardening/release gates unless a specific iteration 3 test is blocked by them.
