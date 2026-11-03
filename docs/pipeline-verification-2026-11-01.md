# pipeline verification · 2026-11-01

## intended behavior and acceptance

- one CI run per PR update, plus main pushes and explicit manual runs; superseded PR runs cancel.
- focused local test selectors during editing; all quality, unit/integration, and UI checks remain required before merge.
- one signed test build reused by both suites; changed inputs reject `--no-build`.
- a missing graphical session or known unchanged UI bootstrap failure stops before another full UI attempt; a repaired environment can be explicitly retried. startup failures and assertion failures remain distinct and neither is a pass.
- compression journeys start from a real encoded synthetic preview; selection, recording, export, keyboard trim, loop/speed, recovery, cancellation, and cleanup remain covered. each UI case stops after its first failed prerequisite.
- captures stay local. no notification, chat lifecycle, release-policy, encoder, or sound changes.

## baseline

read-only GitHub audit: [main run 41295536315](https://github.com/simaopsbarbosa/gifferent/actions/runs/41295536315) took 7m38s with roughly 4s to start, 44s build, 30s unit/integration, and 5m58s UI acceptance. quality passed; two UI cases produced six assertions. [successful run 40973864302](https://github.com/simaopsbarbosa/gifferent/actions/runs/40973864302) spent 5m09s in UI acceptance. paired push/PR runs confirmed duplicated execution. these hosted timings are a baseline, not a same-machine before/after benchmark.

the working tree already contained staged product changes, including UI accessibility-query repairs and removal of the FPS experiment. those edits are preserved; this pipeline change does not commit, revert, or publish them.

## verification results

pending local checks. hosted CI and native UI timing must be measured on the final reviewed commit before claiming improvement or full merge acceptance. real-Mac visual/accessibility review and all release gates remain pending.
