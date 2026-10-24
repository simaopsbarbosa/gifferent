# gif edit model

this document describes the deterministic sequence transform used by the first-release edit pipeline. it does not define trim controls, their presentation, or a visual quality threshold.

## input and output

`GIFEditModel.apply` takes a `CapturedPNGSequence` and `GIFEditParameters`. the frame range uses a zero-based inclusive start and exclusive end. a valid range selects at least one frame and stays within the sequence. selected frames retain their source order and file URLs.

playback speed is a finite positive multiplier. `1` keeps the source timing, values above `1` make playback faster, and values below `1` make it slower. output timestamps start at zero and use `(source timestamp - first selected timestamp) / playback speed`, preserving each selected interval subject to floating-point representation.

`GIFLoopMode.forever` and `.once` pass the selected loop intent alongside the edited sequence. this model does not encode a GIF or choose an encoder.

## errors

empty sequences, empty or out-of-bounds ranges, nonpositive or nonfinite speeds, nonfinite or non-increasing selected timestamps, and timing that overflows or collapses to a non-increasing output timestamp are rejected. the model does not clamp, reorder, extend, or otherwise normalize invalid input. a one-frame selection is allowed and has timestamp zero.

## verification boundary

unit tests prove range behavior, frame identity and order, timing transformation, loop-intent retention, and rejected inputs. preview controls, rendered preview behavior, GIF loop metadata, and agreement between preview and exported timing require later integration with an encoder and are not covered by this model.
