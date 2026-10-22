# gifferent vision

## promise

gifferent turns something happening on a Mac into a shareable GIF with minimal interruption. summon capture, choose a screen, window, or region, record while continuing to use the Mac, then copy, save, or make the GIF smaller. it should feel immediate, native, and quietly playful.

## experience principles

- **fast to start:** the menu bar app runs in the background. `⌃⌥G` opens a full-screen capture overlay. capture should be ready in under one second on the benchmark machine, measured from the hotkey press.
- **precise capture:** select one display, one window, or a region on one display. move and resize a selected region before recording. show a magnifier at dragged corners so precise edges are visible. a subtle recording frame remains visible to the user but never appears in the GIF. window capture follows the selected window as it moves or resizes.
- **stay in flow:** `⌃⌥R` starts recording and stops it when pressed again. when no capture selection exists, it opens selection. the user can use the Mac normally during recording. the cursor is included by default and can be disabled.
- **instant result:** stopping opens a floating GIF preview, with file size, duration, dimensions, and actions. target under two seconds from stop to first usable preview for a 10-second recording on the benchmark machine. this is a target to prove, not a claimed result.
- **share directly:** copy should paste an animated GIF into destinations such as GitHub. `⌘C` is identical to the copy action and shows a brief success message. save and `⌘S` show the standard save dialog. discard is explicit; closing an unexported preview asks before discarding.
- **make smaller with intent:** compression retains the original, switches preview to the result, and offers a back action. a slider controls dithering strength, with resolution choices of original, 75%, 50%, and 25%. destination buttons under `optimize for:` show the destination logo and maximum size, with a safety margin. the first destinations are Discord and GitHub. if a target cannot be reached at an acceptable quality, show the best result and a clear warning.
- **creative restraint:** delight comes from motion, sound, and crisp feedback around real actions. effects never delay capture, obscure content, or make the app harder to use. sound is subtle and optional.

## brand

- working name: **gifferent**.
- character: fun, minimal, quietly playful, confident, and brief.
- image direction: develop the geometric loop-frame concept first, in mostly monochrome with a warm orange accent. small brand accents may appear inside capture and recording UI; the mark should remain recognizable at menu bar size. use dithering effects and animated ascii art when possible, those effects are the ones to be explored.
- native surface first: macOS materials, typography, controls, focus behavior, light/dark appearance, reduced motion, accessibility labels, and keyboard navigation should feel at home on macOS. custom visual moments should support the product rather than imitate a web dashboard.

## voice

- all authored prose in the app, documentation, README, and code comments is lowercase, except proper names, official product names, technical identifiers, commands, and file paths that need exact spelling.
- say only what helps the next action. use short verbs and concrete measurements. avoid jokes in errors, sales language, long tutorials, and celebratory messages after routine actions.
- examples: `record`, `stop`, `copy gif`, `saved`, `copied`, `12.4 mb`, `couldn't reach 10 mb`, `allow screen recording to continue`.
- show progress with a clear state and an unobtrusive animation. always provide text or an accessible equivalent; never rely on sound, color, or animation alone.

## privacy and reliability

- captured pixels and GIF processing stay local. do not upload captures, frames, or derived GIFs to a server.
- guide screen-recording permission setup in the app. explain what is needed in one or two short steps, then recover cleanly when permission changes.
- warn if a recording grows unusually long or large, while allowing the user to stop it. typical recording is under 30 seconds; no silent cutoff is approved.
- restore the last selection on the next activation, with a quick way to reselect. account for a disconnected display or closed window.

## success signals

- a new user can grant permission, capture, record, and paste a GIF without reading a manual.
- the required hotkey-to-ready and stop-to-preview targets are met on a named reference Mac and fixture set.
- exported GIFs play and paste correctly in the tested destinations, and size goals report truthful outcomes.
- routine recording never blocks normal computer use, leaves a capture overlay in the file, or leaks temporary media after discard or a crash. unfinished recordings are cleared on the next launch after a crash.
