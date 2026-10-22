# gifferent agent hub

## authority and workflow

- the user is the product architect. trust their vision. do not silently decide product behavior, visual identity, release policy, or tradeoffs that the documents leave open.
- before implementing a feature, read this file and the linked documents. ask the architect every relevant question needed to make the intended behavior clear. group questions, explain the consequence of each decision, and use Codex multiple choice questions when available. do useful investigation while waiting, but do not implement a dependent choice before the answer.
- proactively flag gaps, conflicts, platform constraints, privacy concerns, and better options. make a specific recommendation with its tradeoff. record unresolved choices in [decisions.md](decisions.md) and ask; do not turn a recommendation into a requirement without the architect's answer.
- preserve approved behavior and scope. changes to a settled product rule need the architect's decision. update the relevant documents in the same change as implementation.
- this is a public macOS product. prioritize stability, predictable performance, privacy, accessibility, and a native feel.

## source of truth

1. [vision.md](vision.md): product promise, brand, and experience rules.
2. [brand.md](brand.md): visual and sound direction, including the mark under development.
3. [mvp.md](mvp.md): release scope and observable behavior.
4. [architecture.md](architecture.md): proposed technical stack, boundaries, and experiments.
5. [definition-of-done.md](definition-of-done.md): required evidence before any feature is complete.
6. [decisions.md](decisions.md): confirmed choices, pending questions, and change log.

if documents conflict, stop dependent work and ask the architect. the most recent explicit answer from the architect overrides an older document; then update the documents.

## implementation rules

- use SwiftUI for all product UI. use AppKit only for macOS capabilities SwiftUI cannot provide cleanly, such as overlay windows, global hotkeys, cursor geometry, or clipboard integration. keep bridges small and testable.
- use public macOS APIs. support macOS 14 and later. the initial release is a notarized direct download and a menu bar app.
- the project's chosen license is AGPL-3.0-or-later. verify every bundled dependency and CLI's license obligations before inclusion; add the full license text and required notices when the source repository and distributable are assembled.
- treat the approved brand image and its usage rules as a release requirement. the loop-frame direction and warm orange accent are selected, but final artwork is still awaiting architect review; do not silently substitute a generic icon.
- screen pixels stay on the device. no cloud compression or screen-content telemetry. any future external transfer requires a new explicit product decision.
- keep the app responsive during capture and encoding. perform expensive work away from the main actor, bound memory and temporary disk use, and handle cancellation and cleanup.
- keep capture, selection, recording, encoding, optimization, export, and UI state behind clear interfaces so alternatives can be benchmarked without rewriting the app.
- choose a bundled existing command-line encoder/optimizer through documented, reproducible benchmarks and license review. do not assume a tool is fastest because of reputation. sign and notarize bundled executables as part of release verification.
- follow the brand and copy rules in [vision.md](vision.md). documentation, in-app copy, and code comments use lowercase prose, except proper names, official product names, identifiers, commands, and file paths when their spelling matters. code identifiers follow Swift conventions.
- avoid unnecessary dependencies, speculative abstractions, broad refactors, and unmeasured performance claims.

## every change

1. ask relevant questions first; capture the architect's answer in the docs.
2. state the intended user behavior and acceptance scenarios before writing code.
3. implement the smallest complete slice, including errors, permissions, accessibility, and cleanup.
4. add or update meaningful unit, integration, and automated acceptance tests. run the relevant checks locally.
5. benchmark any performance-sensitive change against the recorded baseline on the same input and machine. include speed, memory, output size, and visual quality where applicable.
6. run the required build, format, lint, test, and documentation checks from [definition-of-done.md](definition-of-done.md). report exact commands, results, and any real-machine checks that remain unverified.

## review and release

- do not call a feature complete while a required test is failing, skipped without a documented reason, or missing.
- pull requests must identify the behavior changed, test evidence, benchmark evidence when relevant, permission or privacy impact, and documentation updates.
- the architect reviews product decisions and visual work. automated tests and a real-Mac acceptance pass gate release.
