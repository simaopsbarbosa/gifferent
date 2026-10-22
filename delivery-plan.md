# delivery plan

## mandate and boundary

this is the execution plan for the complete first release in [mvp.md](mvp.md). the engineer owns technical decisions, task order, agent assignments, integration, quality, and CI/CD. the architect approves changes to settled product behavior, the final visual and sound identity, and release policy. the engineer records technical decisions and evidence without waiting for routine approval. open product choices in [decisions.md](decisions.md) remain gates for the affected work.

this stage produces documentation only. implementation, repository automation, GitHub settings, signing, and distribution start in the next stage. a passing CI build will never be described as proof of real screen capture, paste into a third-party app, or release readiness.

## operating model

- work in ordered iterations with small, reviewable vertical slices. keep one integration owner responsible for the shared architecture and final result. assign agents bounded tasks with explicit interfaces, acceptance scenarios, tests, and files they may change.
- run independent research, fixture creation, documentation, and focused implementation in parallel when their inputs are stable. serialize changes to shared UI state, the Xcode project, signing, and the capture pipeline when simultaneous edits would create conflicts.
- before each feature slice, write its observable behavior and failure cases in the task or pull request. check [vision.md](vision.md), [brand.md](brand.md), [mvp.md](mvp.md), [architecture.md](architecture.md), [definition-of-done.md](definition-of-done.md), and [decisions.md](decisions.md). raise a product question only when the documents do not settle behavior.
- agents work on dedicated branches or isolated worktrees. one owner integrates each slice after review. no agent may mark its own unverified work complete or bypass a failing required check. the engineer resolves conflicts, runs integration checks, and maintains the dependency order.
- each pull request stays small enough to review, includes relevant documentation, and has evidence for behavior, tests, privacy/permissions, and performance when affected. merge only after the required checks pass. do not let unrelated feature work hide a failed gate.

## dependency order and iterations

the order below is a dependency graph, not a calendar. work within an iteration may overlap when interfaces and fixtures are stable.

| iteration | work packages in dependency order | exit evidence |
| --- | --- | --- |
| 0 · foundation | create the Xcode app and test targets; add AGPL license text, notices inventory, `.gitignore`, deterministic fixtures, documented local commands, formatting, linting, build and test scripts; establish CI on a pinned macOS runner and Xcode version; set up the app state model and injectable seams. start focused feasibility checks for hotkeys, capture permissions, clipboard formats, encoder licensing, and fixture throughput. begin loop-frame studies for later architect review. | a fresh checkout builds; unit, integration, and fixture-driven UI smoke tests run locally and in CI; format, lint, build, and test checks are required for merge; technical risks and open product decisions are logged; no production capture is claimed. |
| 1 · capture selection | permission guide and recovery; menu bar lifecycle; hotkey prototype and conflict behavior; display/window/region selection; geometry across scales and displays; move/resize and magnifier; last valid selection; accessible selection controls. | deterministic tests cover selection and failure states; a real-Mac check confirms permission, hotkeys, magnifier, and normal desktop interaction before depending on the capture path. |
| 2 · record and original GIF | ScreenCaptureKit stream; bounded frame transport; timestamps, cursor option, 24 fps target, recording frame outside output; cancellation and temporary workspace cleanup; encoder benchmarks and license decision; stop, playable original preview, metadata, copy, save, and discard. | complete record-to-export journey passes controlled acceptance tests; real-Mac capture and animated paste are checked; latency, memory, frame loss, bytes, and quality have recorded baselines. |
| 3 · edit and optimize | trim, speed, and loop with preview/export agreement; compression with original recovery; dithering and resolution controls; Discord and GitHub size goals; bounded search and honest failure result. | fixture tests prove timing, loop, dimensions, file validity, settings, and size reporting; benchmark comparisons and visual samples support the chosen optimizer. |
| 4 · hardening and identity | long/large recording warning; target disappearance, permission loss, disk-full and process failures; crash cleanup; VoiceOver, keyboard use, reduced motion, light/dark and high contrast; architect-reviewed mark, color, motion, and optional sound. | all [mvp.md](mvp.md) journeys pass automated acceptance and real-Mac checks; no unresolved release-blocking defect or unapproved brand asset remains. |
| 5 · release | full regression and performance pass; dependency/license audit; sign app and nested tools; notarize and staple the distribution; verify on a clean Mac; prepare release notes and source/notice bundle; publish only after release approval. | reproducible release artifact, checksums, notarization and Gatekeeper evidence, complete test and benchmark report, real-Mac acceptance record, and architect release decision. |

the encoder benchmark, hotkey mechanism, and clipboard representation are experiments whose results determine implementation within their iterations. do not freeze a candidate because it appears in [architecture.md](architecture.md). if a proposed CLI cannot satisfy licensing or quality requirements, record the evidence and choose another compatible CLI before packaging. if the timing targets cannot be met without unacceptable quality or resource use, present measured options to the architect instead of silently weakening the targets.

## decision gates and early risk work

| gate | earliest affected work | resolution needed |
| --- | --- | --- |
| reference Mac and visual quality floor | final encoder and speed selection | record the benchmark machine, OS, power mode, fixture set, percentile, and architect-reviewed quality examples before declaring the speed and size goals met. |
| recording frame placement | window recording and overlay | confirm frame shape and placement, including its exclusion from captured pixels. window disappearance and cross-display behavior are settled in [decisions.md](decisions.md). |
| final loop-frame artwork, color, motion, and sound | branded production UI and release | present small-size, light/dark, high-contrast, and reduced-motion studies for architect approval. studies may proceed in parallel with engineering. |
| destination limits and logo use | size presets and release | recheck official limits and logo terms when implementing the preset and again before release; show the scope and date of each value. |

research tasks may proceed without these answers, but the affected behavior cannot be integrated as a settled product choice. the engineer brings a recommendation, evidence, and a clear tradeoff for each gate.

## task specification for each agent

each assigned task must contain:

1. the user behavior and acceptance scenarios, including denial, cancellation, errors, and cleanup where relevant;
2. the owning interface or files, dependencies, and what is out of scope;
3. expected unit, integration, automated UI, and real-Mac evidence;
4. performance measures and baseline fixtures when the task affects latency, capture, encoding, compression, or memory;
5. documentation to update and any open product decision that blocks the work.

agents may research and prototype behind interfaces while a product decision is pending, but must not ship dependent behavior as a default. the engineer reviews every handoff, checks integration across seams, and owns the final regression and release report.

## repository layout to establish in iteration 0

- `gifferent.xcodeproj/`: app, test targets, shared schemes, and test plans. the project is the build source of truth; pin the chosen Xcode and Swift toolchain after the first reproducible build.
- `Sources/` or an equivalent Xcode project group: UI, selection, capture, recording, encoding, optimization, export, and support code grouped by responsibility. use only the interfaces needed by the current slice.
- `Tests/`: unit, component/integration, UI acceptance, and fixture helpers. keep non-sensitive synthetic frames and expected metadata under version control; never commit screen recordings from users.
- `Benchmarks/`: fixture generation, repeatable commands, machine/environment record, results, and visual comparison instructions. keep large generated outputs outside Git.
- `Scripts/`: one entry point each for format check, lint, build, unit/integration tests, UI acceptance, benchmarks, and release verification. scripts print exact commands and fail on errors.
- `.github/workflows/`: pull-request CI and a separate protected release workflow once executable scripts and schemes exist. add a pull-request template that captures behavior, tests, benchmark evidence, privacy/permission impact, and docs.
- `LICENSE` and `THIRD-PARTY-NOTICES.md`: add full AGPL text and reviewed bundled-tool obligations before code or binaries are distributed. keep binary provenance, version, checksum, architecture, and license evidence beside release instructions.

the names are intended layout, not a reason to create empty directories or placeholder workflows. keep the actual project structure as small as the first working slice permits.

## CI and release design

### pull requests

- trigger on pull requests and changes to the main branch. use a pinned macOS runner label and explicitly select the intended Xcode installation; update both deliberately after a verified build. avoid `macos-latest` for a release-critical gate.
- run documentation/link consistency checks, formatting check, strict lint, build for the macOS 14 deployment target, unit/integration tests, and deterministic XCTest UI acceptance. use the same repository scripts locally and in CI. upload `.xcresult` and relevant logs on failure; retain fixtures and test outputs according to a documented policy.
- run a fixture-based CLI integration test when an encoder is added. check its version, hash, architecture, execution, and output validity. pull-request jobs use no Developer ID or notarization credentials.
- make the checks required before merge after the first working workflows pass. configure least-privilege workflow permissions and concurrency cancellation for superseded pull-request runs. protect `main` from direct unreviewed feature pushes.
- CI runs controlled UI paths and does not request live screen-recording permission on a shared runner. hardware-dependent acceptance belongs in the real-Mac gate, with its result recorded alongside the release candidate.

### release candidate and distribution

- build from a clean, reviewed commit or tag after the full CI suite passes. run a separate release workflow with restricted credentials and explicit approval at the publishing step.
- verify the bundled tools and notices; sign nested executables and the app with the appropriate Developer ID identity and hardened runtime; submit the distribution to Apple's notarization service, staple the ticket, and verify signature and Gatekeeper acceptance. preserve the build log, commit, toolchain, artifact checksum, and notarization result.
- install the candidate on a clean supported Mac. run the complete real-Mac acceptance checklist: first-run permission and denial, both global hotkeys and conflict behavior, 1×/2× and multi-display selection, moving/resizing a window, cursor/frame exclusion, long recording warning, animated clipboard paste into a real target, save, editing, compression, crash cleanup, accessibility, appearance, and sound. record machine, OS, power mode, and outcomes.
- the architect supplies Apple Developer access and participates in final visual and release approval at this gate. credentials stay outside the repository and pull-request jobs. do not publish a release with missing signing, notarization, license, brand, or real-Mac evidence.

## completion rules

- an iteration exits only when its behavior, tests, documentation, and applicable measurements satisfy [definition-of-done.md](definition-of-done.md). an experimental result may close a research task, but it does not complete a user feature.
- a feature's test matrix is proportional to the seams it changes; no fabricated UI or performance claim can substitute for observed results. mark unavailable hardware checks as pending and keep release blocked until they pass.
- record decisions in [decisions.md](decisions.md), benchmark evidence in the benchmark log, and release evidence with the release candidate. when documents disagree, stop the affected implementation and resolve the conflict before integration.
