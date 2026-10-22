# first release scope

## supported product

- macOS 14 and later; notarized direct download; menu bar presence without a Dock icon.
- background activation with configurable `⌃⌥G` capture and `⌃⌥R` start/stop hotkeys. settings warn about conflicts. selection opens when record is pressed before choosing a target.
- full-screen selection overlay with display, selected-window, and free-region modes. capture one monitor at a time. regions can be moved and resized before recording. a corner magnifier appears while dragging. the last selection is restored when valid; reselect is immediate.
- record at an initial 24 fps target. capture the cursor by default, with a setting to disable it. show a subtle recording frame outside the resulting GIF. keep normal Mac interaction available while recording. follow a selected window as it moves or resizes.
- stop with the same hotkey. show a floating, animated preview with file size, duration, dimensions, and clear processing status. offer copy, save, discard, and compress. `⌘C` copies and confirms success; `⌘S` opens the save dialog. closing an unexported preview asks before discarding.
- trim the beginning and end before export. choose playback speed, which changes exported duration. choose loop forever or once. preview and export must agree.
- compression uses bundled local command-line tooling. preserve the original; show compressed output with a back action. offer dithering-strength slider, original/75%/50%/25% resolution choices, and goal buttons for Discord and GitHub. each button shows the destination logo and current published maximum. aim below the limit with a safety margin. automatically search resolution, frame rate, palette, and dithering settings for the smallest file under the target. report the best attempt and a warning if the goal cannot be met acceptably.
- guided screen-recording permission setup; clear failures for missing permissions, hotkey conflict, unavailable display/window, full disk, encoder failure, and failed clipboard or save operations.
- subtle optional interaction sounds, brief motion feedback, reduced-motion support, keyboard navigation, and accessible labels.

## acceptance journeys

| journey | required observable outcome |
| --- | --- |
| first launch | permission guide appears when needed; menu bar app remains usable after permission is granted or refused. |
| region capture | user selects, moves, and resizes a region; corner magnifier assists the drag; only the selected pixels are encoded. |
| display and window capture | one display or one window is selected; moving or resizing the window keeps the recording attached to it. |
| background use | other apps receive normal mouse and keyboard input while recording; the record hotkey still stops capture. |
| preview and export | stop opens an animated preview; metadata matches exported GIF; copy and `⌘C` paste animation into the tested destination; save and `⌘S` produce the same valid file. |
| editing | trim, speed, and loop changes are visible in preview and persist in copied and saved GIFs. |
| compression | original is recoverable with back; resolution and dithering controls alter the result; preset reports actual size against its target, including failure to meet it. |
| failure recovery | permission loss, disappearing target, low disk space, encoder failure, and hotkey conflict produce actionable states and clean up temporary files. after a crash, unfinished recordings are deleted on next launch rather than restored. |

## release boundary

- no account, cloud upload, screen-content analytics, video export, or captured audio.
- recording spans one monitor at a time. cross-display region recording is outside this release.
- no Slack size-goal button until a useful target is defined. no restoration of unfinished recordings after a crash.
- no promise of a specific size, frame rate, or latency until the benchmark environment and quality floor are agreed and measured.

## destination limit policy

- source limits must be verified from each destination's official documentation before release and periodically afterward. show the exact scope of a limit, such as file attachment versus repository file.
- current research: Discord's free upload limit is [20 mb](https://support.discord.com/hc/en-us/articles/25444343291031-File-Attachments-FAQ), and GitHub's issue/comment GIF attachment limit is [10 mb](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/attaching-files). these are dated facts, not permanent product constants. [Slack's standard file upload limit is 1 gb](https://slack.com/help/articles/201330736-Add-files-to-Slack), so the architect excluded its preset until a useful size goal is defined.
