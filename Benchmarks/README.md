# benchmark evidence

use the same synthetic source fixtures and machine configuration when comparing a change against its baseline. keep generated frames and outputs under `Benchmarks/generated/` or `Benchmarks/outputs/`; both are ignored by Git. commit the fixture generator, exact commands, small reviewable results, and representative visual comparisons once they exist.

## synthetic source fixture

generate the default 10-second, 24 fps fixture with Python's standard library:

```sh
python3 Benchmarks/generate_fixture.py --output Benchmarks/generated/reference-640x360 --width 640 --height 360 --seed 7 --frames 240
```

the output directory must be new. the generator writes `frame_0000.png` through `frame_0239.png` and a `manifest.json`. frame `n` starts at `n / 24` seconds; each frame lasts `1 / 24` second. the manifest records the seed, dimensions, frame count, rate, and timing rule. the pixels are synthetic: bitmap text, flat UI shapes, a moving cursor-like mark, and moving color gradients. its colors and layout are benchmark inputs, not approved product artwork. no screen content is read.

for a quick smoke run, use `--frames 6 --width 320 --height 180` with a different new output directory. keep the same seed, dimensions, and frame count for every candidate in one comparison.

for each run, record:

- commit, date, macOS and Xcode versions, Mac model, chip, memory, power mode, and thermal conditions;
- fixture name, dimensions, duration, frame rate, cursor content, motion and text characteristics;
- tool name, version, checksum, license, flags, and whether encoding happens during capture or after stop;
- sample count, warmup policy, timing statistic, start-to-ready and stop-to-preview latency, total processing time, peak memory, temporary disk use, CPU use, dropped frames, and output bytes;
- validity and visual review of animation, text, motion, dithering, and color; include reviewer and known limits;
- baseline and candidate results on the same input and machine, with a conclusion tied to measured evidence.

the speed goals in [vision.md](../vision.md) remain targets until runs on an agreed reference Mac and fixture set establish them. the acceptable visual quality floor is an open product decision in [decisions.md](../decisions.md).
