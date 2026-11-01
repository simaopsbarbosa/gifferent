# gifferent agent hub

## authority and source of truth

- the architect owns settled product behavior, final visual/sound identity, and release policy. the lead engineer owns architecture, implementation, task order, integration, verification, and CI/CD. proceed with routine engineering choices; ask only about unresolved product decisions, grouping questions and explaining tradeoffs.
- read the documents relevant to the change, in this order of authority: [vision.md](vision.md), [brand.md](brand.md), [mvp.md](mvp.md), [architecture.md](architecture.md), [definition-of-done.md](definition-of-done.md), [decisions.md](decisions.md), and [delivery-plan.md](delivery-plan.md). the latest explicit architect answer overrides older prose; update affected documents. stop dependent work on an unresolved conflict.
- planning is complete. follow the delivery dependency order, preserve approved scope, and record new decisions and unresolved product questions in `decisions.md`. recommendations become product requirements only after the architect answers.
- keep one integration owner and one working chat by default. reuse a suitable checkout. isolate independent delegated work when warranted; serialize shared UI state, project, signing, and capture-pipeline edits. never close or archive user chats as verification housekeeping.

## implementation

- build a stable, private, accessible, native macOS 14+ menu bar app using public APIs. use SwiftUI for product UI; keep AppKit bridges small and limited to capabilities SwiftUI cannot provide cleanly.
- pixels and GIF processing stay local. no cloud compression or screen-content telemetry; external transfer needs a new explicit product decision.
- keep expensive capture/encoding work off the main actor, bound memory and temporary disk, and handle cancellation, errors, and cleanup. preserve clear capture, selection, recording, encoding, optimization, export, and UI boundaries without speculative abstractions or broad unrelated refactors.
- choose bundled encoders through reproducible comparisons and license review. the project is AGPL-3.0-or-later; include required full license texts, notices, source/build materials, and executable signing/notarization evidence before distribution. avoid unnecessary dependencies and unmeasured performance claims.
- use the approved static orange mark in `Brand/mark-light.svg` and `Brand/mark-dark.svg` under the brand usage rules. optional mark motion and sound require architect approval.
- app copy, documentation, and comments use lowercase prose except proper names, official product names, identifiers, commands, and paths. Swift identifiers follow Swift conventions.

## each change

1. state observable behavior and acceptance scenarios before implementation, including affected permission, failure, cancellation, accessibility, and cleanup paths. do not reopen settled product questions.
2. implement the smallest complete slice and update affected source documents in the same change.
3. add meaningful tests at the lowest layer that proves the behavior. keep representative UI journeys and UI wiring coverage; put exhaustive timing, metadata, and error combinations in unit/integration tests.
4. benchmark changed performance paths on the same machine, fixtures, OS, and power mode as the baseline, including time, memory, bytes, and visual quality where relevant. compare credible alternatives for important pipeline choices.

## verification stages

- development: use focused unit/integration selectors and affected quality checks from [README.md](README.md). run selected UI journeys for changed UI wiring. reuse evidence while its inputs remain unchanged; do not repeat full local and hosted suites after every edit.
- merge: the final candidate must pass the complete quality, unit/integration, and deterministic UI suites in CI. `main` requires an up-to-date PR with `quality` and `tests` passing, including administrator merges. build test bundles once and refuse stale reuse. a focused run, skipped required test, or runner-startup failure is never full acceptance.
- release: retain the full regression/performance matrix, real-Mac permission/hotkey/multi-display/animated-paste/accessibility checks, visual review, licenses/source delivery, signing, notarization, clean-Mac acceptance, and explicit architect release approval in [definition-of-done.md](definition-of-done.md) and [delivery-plan.md](delivery-plan.md).
- prefer scripts and XCTest for repeatable checks. use computer interaction for a specific native visual/system observation that automated checks cannot establish, stating that observation first.
- on UI bootstrap failure, preserve logs/results and stop retries until session, signing, or toolchain prerequisites change. fix product assertion failures separately; never skip the merge gate or retry unchanged failures to green.
- the integration owner checks CI for the final commit, reads failed-job logs, and reports results and next actions. use bounded waits at sensible intervals and do independent work while checks run. rerun only failed jobs when their failure was transient; do not push unchanged code merely to retrigger CI or change GitHub notification preferences.
- PRs and final handoffs state behavior, exact checks/results, relevant benchmarks, privacy/permission impact, documentation changes, and pending real-Mac evidence. do not call a feature complete with missing or failing required evidence. never present CI success as proof of actual screen capture, third-party paste, or release readiness.
