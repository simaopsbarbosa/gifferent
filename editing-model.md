# gif edit model

this document describes the deterministic sequence transform used by the first-release edit pipeline. the approved controls are two timeline handles, a 0.5×–2× speed slider in 0.1× steps centered on 1×, and forever or once loop selection. this edit slice does not set a visual quality threshold.

## input and output

`GIFEditModel.apply` takes a `CapturedPNGSequence` and `GIFEditParameters`. the frame range uses a zero-based inclusive start and exclusive end. a valid range selects at least one frame and stays within the sequence. selected frames retain their source order and file URLs.

playback speed in the interface is from `0.5` through `2` in `0.1` steps. `1` keeps the source timing, values above `1` make playback faster, and values below `1` make it slower. output timestamps start at zero and use `(source timestamp - first selected timestamp) / playback speed`, preserving each selected interval subject to floating-point representation.

`GIFLoopMode.forever` and `.once` pass the selected loop intent alongside the edited sequence. forever output uses a zero-count loop extension; once output omits the loop extension. the ImageIO candidate reads back GIF metadata before an edit becomes the current preview. this does not select a release encoder.

## errors

empty sequences, empty or out-of-bounds ranges, nonpositive or nonfinite speeds, nonfinite or non-increasing selected timestamps, and timing that overflows or collapses to a non-increasing output timestamp are rejected. the model does not clamp, reorder, extend, or otherwise normalize invalid input. a one-frame selection is allowed and has timestamp zero.

## verification boundary

unit and coordinator tests cover range behavior, frame identity and order, timing transformation, loop intent, newest-request handling, workspace cleanup, and export of the current validated GIF. deterministic UI acceptance checks the two accessible handles, speed control, and loop control. real screen capture and animated paste into GitHub still require real-Mac acceptance.
