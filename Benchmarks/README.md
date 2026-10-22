# benchmark evidence

use the same synthetic source fixtures and machine configuration when comparing a change against its baseline. keep generated frames and outputs under `Benchmarks/generated/` or `Benchmarks/outputs/`; both are ignored by Git. commit the fixture generator, exact commands, small reviewable results, and representative visual comparisons once they exist.

for each run, record:

- commit, date, macOS and Xcode versions, Mac model, chip, memory, power mode, and thermal conditions;
- fixture name, dimensions, duration, frame rate, cursor content, motion and text characteristics;
- tool name, version, checksum, license, flags, and whether encoding happens during capture or after stop;
- sample count, warmup policy, timing statistic, start-to-ready and stop-to-preview latency, total processing time, peak memory, temporary disk use, CPU use, dropped frames, and output bytes;
- validity and visual review of animation, text, motion, dithering, and color; include reviewer and known limits;
- baseline and candidate results on the same input and machine, with a conclusion tied to measured evidence.

the speed goals in [vision.md](../vision.md) remain targets until runs on an agreed reference Mac and fixture set establish them. the acceptable visual quality floor is an open product decision in [decisions.md](../decisions.md).
