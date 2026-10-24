# performance reference

the architect selected this development machine as the first release reference on 2026-10-23:

- MacBook Air, model identifier `Mac14,2`, Apple M2, 8 GB memory.
- macOS 27.0.1, build `26A434`, at the decision snapshot. low power mode is off (`pmset` reports `lowpowermode 0`).
- use published synthetic fixtures, one cold run followed by at least seven warm runs per candidate in alternating order. report every raw sample, median, and p90.
- record the actual OS build, power mode, thermal condition, toolchain, fixture checksum, and binary checksum for every run. results from a changed environment form a separate series.

this file selects the environment; it contains no speed result or quality claim.
