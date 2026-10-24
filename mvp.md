# first release scope

## supported product

- macOS 14 and later; notarized direct download; menu bar presence without a Dock icon.
- background activation with configurable `⌃⌥G` capture and `⌃⌥R` start/stop hotkeys. settings warn when a shortcut is unverified and ask the user to test it from another app; receiving the shortcut clears that warning. selection opens when record is pressed before choosing a target.
- full-screen selection overlay with display, selected-window, and free-region modes. capture one monitor at a time. regions can be moved and resized before recording. a corner magnifier appears while dragging. the last selection is restored when valid; reselect is immediate.
- record at an initial 24 fps target. capture the cursor by default, with a setting to disable it. show a thin, high-contrast outline just outside a selected region or window, with a small `recording` label at its top edge. adapt it to light and dark backgrounds and keep it out of the GIF. keep normal Mac interaction available while recording. follow a selected window as it moves or resizes.
- if a selected window moves to another display, keep following it. if it is minimized or closed, stop recording with a clear message and keep usable captured frames as a partial result. if there are no usable frames, show an error and clean up.
- if a selected display disconnects during recording, stop with a clear message and keep usable captured frames as a partial result. if there are no usable frames, show an error and clean up.
- stop with the same hotkey. show a floating, animated preview with file size, duration, dimensions, and clear processing status. offer copy, save, discard, and compress. `⌘C` copies and confirms success; `⌘S` opens the save dialog. closing an unexported preview asks before discarding.
- trim the beginning and end before export with two timeline handles. choose playback speed from a 0.5×–2× slider in 0.1× steps, centered at 1×. choose loop forever or once. preview and export must agree.
- compression uses bundled local command-line tooling. preserve the original; show compressed output with a back action. offer dithering-strength slider, original/75%/50%/25% resolution choices, and goal buttons for Discord and GitHub. each button shows the destination logo and current published maximum. aim below the limit with a safety margin. automatically search resolution, frame rate, palette, and dithering settings for the smallest file under the target. report the best attempt and a warning if the goal cannot be met acceptably.
- guided screen-recording permission setup; clear failures for missing permissions, hotkey conflict, unavailable display/window, full disk, encoder failure, and failed clipboard or save operations.
- retain temporary completed media while its preview is active. remove it when the preview closes after export or after confirmed discard; remove orphaned preview media on the next launch after a crash without touching exported files.
- subtle optional interaction sounds, brief motion feedback, reduced-motion support, keyboard navigation, and accessible labels.

## acceptance journeys

| journey | required observable outcome |
| --- | --- |
| first launch | permission guide appears when needed; menu bar app remains usable after permission is granted or refused. |
| region capture | user selects, moves, and resizes a region; corner magnifier assists the drag; only the selected pixels are encoded. |
| display and window capture | one display or one window is selected; moving or resizing the window keeps the recording attached to it. |
| background use | other apps receive normal mouse and keyboard input while recording; the record hotkey still stops capture. |
| preview and export | stop opens an animated preview; metadata matches exported GIF; copy and `⌘C` paste animation into GitHub on a real Mac; save and `⌘S` produce the same valid file. |
| editing | two timeline handles trim the beginning and end; the 0.5×–2× speed slider starts at 1×; speed and loop changes are visible in preview and persist in copied and saved GIFs. |
| compression | original is recoverable with back; resolution and dithering controls alter the result; preset reports actual size against its target, including failure to meet it. |
| failure recovery | permission loss, disappearing target, low disk space, encoder failure, and hotkey conflict produce actionable states and clean up temporary files. after a crash, unfinished recordings are deleted on next launch rather than restored. |

## release boundary

- no account, cloud upload, screen-content analytics, video export, or captured audio.
- recording spans one monitor at a time. cross-display region recording is outside this release.
- no Slack size-goal button until a useful target is defined. no restoration of unfinished recordings after a crash.
- no promise of a specific size, frame rate, or latency until the benchmark environment and quality floor are agreed and measured.

## destination limit policy

- source limits must be verified from each destination's official documentation before release and periodically afterward. show the exact scope of a limit, such as file attachment versus repository file.
- 2026-10-24 research snapshot: Discord's non-Nitro attachment FAQ lists 20 mb and notes experiments may give selected users higher limits; GitHub's issue, pull request, and comment image/GIF attachments are limited to 10 mb. scope, account conditions, and official mark-use sources are recorded in [the destination limits research note](Benchmarks/destination-limits-2026-10-24.md). these are dated facts, not permanent product constants. [Slack's standard file upload limit is 1 gb](https://slack.com/help/articles/201330736-Add-files-to-Slack), so the architect excluded its preset until a useful size goal is defined.
