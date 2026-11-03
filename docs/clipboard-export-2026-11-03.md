# separate clipboard export · 2026-11-03

## behavior

- `copy image` / `⌘C` retains the existing GIF image-data action.
- `copy file` / `⌘⇧C` publishes the current preview as a native GIF file attachment, without a PNG or TIFF alternative. feedback says `file copied`.
- both actions use the same export gating and failure handling. the file adapter copies bytes off the main actor and retains its private attachment independently of recording-session cleanup. subsequent file copies replace it atomically; retained/staging limits and lifetime are recorded in [decisions.md](decisions.md).
- no pixel data leaves the Mac automatically, and no new permission or dependency is introduced.

## verification

- `bash Scripts/test-unit.sh`: 197 passing tests, zero failures/skips. result: `.build/ci/test-unit-jPUHx1/Result.xcresult`; log: `/private/tmp/gifferent-copy-file-full-tests.log`.
- `bash Scripts/quality.sh` and `git diff --check`: pass. log: `/private/tmp/gifferent-copy-file-quality.log`.
- native clipboard integration tests use unique named pasteboards and private test directories. they verify two-frame GIF byte identity, file URL representation, absence of flattened image alternatives, file permissions, survival after source cleanup and store recreation, replacement without accumulation, missing/oversized source failures, cancellation, and unchanged image-copy behavior.
- coordinator tests verify edited and compressed output routing, separate image/file adapters, source cleanup with attachment survival, failed copy retaining the preview, and blocking closure while file export is pending.
- a deterministic UI journey covers both buttons, `⌘C`, `⌘⇧C`, current once-loop output, and file survival after closing the preview. test bundles compile; the UI journey was not executed because acceptance remains deferred at the architect's request.
- [clipboard benchmarks](../Benchmarks/clipboard-copy-2026-11-03.md) compare both production adapters on the same animated fixtures, recording time, peak process RSS, bytes, frame count, and hashes. no encoder change or visual-quality loss occurs because copied files are byte-identical.

## pending evidence

GitHub paste in the actual browser, native layout and keyboard/VoiceOver review, and final UI acceptance remain unverified. pasteboard representation checks do not establish browser compatibility. the existing release gates remain in force.
