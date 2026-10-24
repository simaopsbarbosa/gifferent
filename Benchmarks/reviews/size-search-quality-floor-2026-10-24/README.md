# size-search quality-floor review — 2026-10-24

## purpose

this is a representative visual floor check for the proposed size-search scale and frame-rate candidates. it retains 16 looping samples from two synthetic benchmark profiles: mostly-static UI and high-motion gradient/cursor. the page shows every scale at 24 fps, every frame rate at 100% scale, and the joint 25% / 8 fps corner. the other measured combinations are listed in `summary.json`, but their animated files were removed to keep the review small.

the page does not declare that any candidate passes the approved floor. it does not prove every scale/rate interaction, and it does not select settings or change product behavior. architect review is requested for the seven new preview points per profile:

- mostly-static UI: 100% at 18, 12, and 8 fps; 75%, 50%, and 25% at 24 fps; and 25% at 8 fps.
- high-motion gradient/cursor: the same seven scale/rate points.

the 100% / 24 fps samples are the previously reviewed q90 reference outputs and are included only for comparison. the remaining points are new single-run candidates. the page has a maximum-scale filter: it shows only samples at or below the selected maximum, matching the proposed rule that the user's scale is the search ceiling.

## measurement and validation

the sources are the published 640 × 360, 240-frame, 24 fps synthetic fixtures generated with seed 7. their manifests and all-frame SHA-256 digests are recorded in `summary.json`; no screen content is used. Gifski 1.34.0 encoded all candidates at quality 90 with `--repeat 0 --no-sort`. ImageMagick 7.1.2-34 prepared 75%, 50%, and 25% source frames with the Lanczos filter.

target frames use nearest-time source selection with ties rounded forward: `source_index = floor(output_index × 24 / target_fps + 0.5)`. this is a deterministic temporal resampling rule for the discrete 24 fps fixture. 18 fps has alternating source-frame gaps because 24 is not an integer multiple of 18. GIF output timing is independent and exact: each candidate was checked against the benchmark's cumulative rounded-centisecond schedule, 10.0-second total duration, frame count, dimensions, and infinite-loop metadata.

all 32 measured combinations across the two profiles passed the exact timing and metadata checks. there were zero exact-duration, cadence, dimension, frame-count, or loop failures. output bytes and the single Gifski process wall time are recorded per combination. rescaling time is recorded separately and reused across frame-rate candidates. the 100% / 24 fps baseline timing comes from its published full-matrix cold sample; it was reused and not encoded again.

the runs used the pinned local Gifski 1.34.0 arm64 binary (SHA-256 `947969d778a894e9b2c281bc96c6644ba88a16aba6e64b3cd2a4f5e219d8de46`) on an Apple M2 Mac with 8 GB memory, macOS 27.0.1, and Xcode 27.1. each new setting has one encode sample, so the recorded runtime is descriptive rather than a stable performance estimate. no CPU or memory comparison was part of this review.

the committed helper `Benchmarks/create_size_search_review.py` validates fixture hashes and q90 baselines, generates every 4×4 scale/rate combination for the four published profiles, records one encode time per new combination, and rejects any output that misses the metadata contract. the run used these local inputs and command; fixture and baseline media are intentionally not committed:

```sh
PYTHONPYCACHEPREFIX=/private/tmp/gifferent-size-search-pycache python3 Benchmarks/create_size_search_review.py \
  --fixtures-json /private/tmp/size-search-review-fixtures.json \
  --baselines-json /private/tmp/size-search-review-baselines.json \
  --gifski /private/tmp/gifski-target-1.34.0/release/gifski \
  --output /private/tmp/gifferent-size-search-review-generated
```

the input maps point to the published fixture directories and full-matrix q90 outputs under `/private/tmp`. after measurement, only the two already-reviewed profiles and 16 selected animations were kept in this review; other generated GIFs were deleted. `summary.json` contains the measurements for the two relevant profiles.

## limitations

- the approved quality floor is: native-scale text legible, cursor edges clear, no distracting gradient banding or flicker; differences visible only at 2× may be acceptable. this page gathers review evidence and makes no pass/fail judgment.
- only the 16 listed animated combinations are retained. the other 16 measured combinations are not animated here; see `summary.json` for their bytes, timings, hashes, and timing validation.
- the synthetic profiles isolate UI text/caret and gradient/cursor stresses; they do not represent every captured application, display scale, color profile, or motion pattern.
- GIF centisecond timing is quantized. the validator checks the exact cumulative rounding schedule for each target rate, rather than requiring every frame delay to equal one constant number of centiseconds.
- Gifski quality is held at 90. this is a scale/rate review, not a quality-setting sweep or encoder selection.
