# gif edit model

this document describes the deterministic sequence transform used by the first-release edit pipeline. the approved controls are two timeline handles, a 0.25×–3× speed menu in 0.25× steps initially at 1×, an output FPS menu (50/45/30/24/20/15/10, initially 50), and forever or once loop selection. this edit slice does not set a visual quality threshold.

## input and output

`GIFEditModel.apply` takes a `CapturedPNGSequence` and `GIFEditParameters`. the frame range uses a zero-based inclusive start and exclusive end. a valid range selects at least one frame and stays within the sequence. selected frames retain their source order and file URLs; output sampling may omit frames.

playback speed in the interface is from `0.25` through `3` in `0.25` steps. validated speed and FPS persist across recordings and launches. `1` keeps the source timing, values above `1` make playback faster, and values below `1` make it slower. output timestamps start at zero and use `(source timestamp - first selected timestamp) / playback speed`, before output sampling. the sampler evaluates this final playback timeline at the selected FPS, holds the most recent captured frame, coalesces repeated source-frame selections, and rounds cumulative boundaries to centiseconds. the terminal boundary retains the rounded speed-adjusted duration, with a 20 ms minimum for very short clips. the FPS ceiling of 50 avoids 10 ms frame delays that browsers can clamp to 100 ms. sparse captures do not gain invented visual detail.

`CapturedPNGSequence.finalFrameDuration` carries the terminal interval when an edit cannot express it with a later frame-start timestamp. a trim ending inside the source uses the next source timestamp to retain the last selected frame's own interval. a trim reaching the source end uses its explicit terminal interval, or the last source interval when none is available; a single-frame source defaults to `1 / 24` second. speed scales this terminal interval too, so a one-frame trim at 2× does not revert to normal-speed timing. the encoder rounds the complete schedule to cumulative centisecond boundaries and rejects nonpositive or unrepresentable intervals. coordinator validation compares every expected delay before publishing a replacement.

`GIFLoopMode.forever` and `.once` pass the selected loop intent alongside the edited sequence. forever output uses a zero-count loop extension; once output omits the loop extension. the ImageIO candidate reads back GIF metadata before an edit becomes the current preview. this does not select a release encoder.

## errors

empty sequences, empty or out-of-bounds ranges, nonpositive or nonfinite speeds, nonfinite or non-increasing selected timestamps, and timing that overflows or collapses to a non-increasing output timestamp are rejected. the model does not clamp, reorder, extend, or otherwise normalize invalid input. a one-frame selection is allowed and has timestamp zero.

## verification boundary

unit and coordinator tests cover range behavior, frame identity and order, timing transformation, loop intent, newest-request handling, workspace cleanup, and export of the current validated GIF. deterministic UI acceptance checks the two accessible handles, speed control, and loop control. real screen capture and animated paste into GitHub still require real-Mac acceptance.

encoded fixture tests also decode selected frame colors/order and exact delays across boundary trims, irregular timestamps, speed extremes, and both loop modes. UI acceptance changes the trim, speed and loop settings, then reads copied and saved GIF bytes and metadata. the detailed matrix and evidence are in [the editing and optimization acceptance report](editing-optimization-evidence-2026-10-25.md).
