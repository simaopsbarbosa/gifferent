# development

use Xcode 27.1 (build 27A9275) for local development. open `gifferent.xcodeproj` with the shared `gifferent` scheme. during development, run the tests and quality checks affected by the change:

```sh
bash Scripts/quality.sh
bash Scripts/test-unit.sh gifferentTests/GIFEditModelTests
bash Scripts/test-ui.sh gifferentUITests/MenuBarSmokeTests/testRecordingActionOpensPreviewAndKeepsExportAfterClose
```

selectors run only the named class or method, after building the test bundles. use `gifferentTests/ClassName/testMethod` or `gifferentUITests/ClassName/testMethod`; omit selectors for the full target. UI runs always include a launch preflight.

for a full local rehearsal of the merge gate:

```sh
bash Scripts/ci-local.sh
```

CI runs quality and unit/integration checks once per PR update and on `main` pushes; UI acceptance runs locally only. feature-branch pushes do not duplicate the PR run. manual workflow dispatch is available for branch diagnostics. `main` protection requires `quality` and `tests` from an up-to-date PR, including administrator merges; no human approval count is imposed. run relevant UI acceptance on the final candidate and report it in the PR.

`Scripts/ci-local.sh` checks the pinned toolchain, runs the shared quality checks, builds the app and test bundles once, then runs unit/integration and UI acceptance without rebuilding. it stops on failure and stores logs and `.xcresult` bundles under `.build/ci/`. a UI launch preflight runs before the remaining journeys. no signing credentials are needed.

to share a build across focused checks:

```sh
bash Scripts/build-tests.sh
bash Scripts/test-unit.sh --no-build gifferentTests/GIFEditModelTests
bash Scripts/test-ui.sh --no-build gifferentUITests/MenuBarSmokeTests/testLaunchShowsIdleContentAndQuitAction
```

`--no-build` rejects missing or changed source, project, resource, toolchain, or signing inputs. rebuild after those inputs change. test artifacts use `.build/ci/TestDerivedData`, separate from manual app builds. `GIFFERENT_ARTIFACTS_DIR` changes the evidence root. `GIFFERENT_SKIP_TOOLCHAIN_CHECK=1 bash Scripts/ci-local.sh` permits a local diagnostic run with another Xcode; that result does not establish CI compatibility.

UI tests need a logged-in graphical macOS session that permits Xcode automation. scripts check that session, then run one launch test. a failure before any UI case starts records a local bootstrap blocker and stops the remaining suite. subsequent attempts in the same environment fail immediately with the evidence path. after repairing the session/signing policy, use `bash Scripts/test-ui.sh --retry-bootstrap` once to verify the repair. product assertion failures remain failures and do not create an environment blocker. test timeouts bound individual cases; there are no automatic retries to green.

deterministic UI tests use synthetic frames and injected clipboard/save adapters without screen permission. compression journeys start at an encoded fixture preview; separate journeys retain selection, record-to-export, keyboard editing, cancellation, and cleanup coverage. actual menu bar interaction, permissions, shortcut delivery, animated paste, visual feel, and release checks remain real-Mac acceptance gates in [delivery-plan.md](delivery-plan.md).

test builds use ad hoc signing by default. when local policy requires the project's configured Apple Development identity, set `GIFFERENT_TEST_DEVELOPMENT_TEAM` consistently for build and test commands. a blocked runner never counts as passing UI acceptance.

for a reliable local Screen Recording permission check, choose an Apple Development team in Xcode's signing settings and run `bash Scripts/build.sh`. unsigned or ad hoc builds may lose the permission association after a rebuild. after enabling access in System Settings, quit and reopen gifferent before checking again. release signing and notarization remain separate from test builds.
