# ImageMagick cache resource audit — 2026-10-24

## scope and result

this bounded audit exercised the existing `ExperimentalImageMagickCompressor` command shape against a synthetic high-motion GIF. no app files or benchmark fixtures were changed. the executable was the machine's exploratory Homebrew build, ImageMagick 7.1.2-34 Q16-HDRI arm64, not a pinned release binary.

the operation failed with `cache resources exhausted` at every tested disk-cache limit, including 500 MiB. the synthetic input and captured-frame fixture total 13,253,526 bytes (12.64 MiB), leaving at most 499.36 MiB of the app's 512 MiB session quota before reserving any compressed output. since the required ImageMagick pixel cache exceeds a 500 MiB cap, this fixture cannot fit within the current per-session quota even before output space is reserved. the current prototype is not integrated, so this is a resource-fit finding for its command and limits, not an app failure or encoder selection.

`-limit memory 256MiB` did not cap process resident memory: observed peak RSS varied from 303.83 MiB to 622.88 MiB across failed runs. these values are measurements of this exploratory build and fixture only.

## fixture and command

- fixture profile: `high-motion-gradient-cursor`, seed 7, 640×360, 240 frames, 24 fps, 10 seconds.
- generated PNG frame bytes: 2,078,810.
- ImageIO candidate GIF used as compressor input: `Benchmarks/outputs/imageio-app-high-motion-gradient-cursor-20261024/gifs/imageio-app/warm-01.gif`, 11,174,716 bytes.
- total known session media represented by these inputs: 13,253,526 bytes.
- the app's `GifferentRuntime.recordingWorkspaceQuotaBytes` is 512 × 1,024 × 1,024 bytes; the workspace retains at least 64 MiB free on the volume.

the executable was `/opt/homebrew/bin/magick`. each run used the same arguments and a fresh private mode-0700 cache directory; only the numeric disk-cache limit changed:

```text
/opt/homebrew/bin/magick \
  -limit memory 256MiB \
  -limit map 512MiB \
  -limit disk <cap-bytes> \
  -limit thread 2 \
  -define registry:temporary-path=<private-cache-directory> \
  <synthetic-source.gif> \
  -coalesce \
  -dither FloydSteinberg \
  -define dither:diffusion-amount=35% \
  -colors 256 \
  -layers Optimize \
  gif:-
```

stdout was redirected to a temporary output file. a Python driver polled the process and summed files below the temporary root every 5 ms, recording the largest sample. after each child exited, a fresh driver process read `resource.getrusage(resource.RUSAGE_CHILDREN)` for `ru_maxrss`, `ru_utime`, and `ru_stime`. macOS reports `ru_maxrss` in bytes. sampled temporary bytes include the cache directory and output file, but not the source GIF stored outside that temporary root.

## results

all runs exited 1 with ImageMagick's `cache resources exhausted` error. no completed GIF was produced. RSS is the raw child maximum converted from bytes to MiB (1 MiB = 1,048,576 bytes). temporary high-water is a 5 ms sampled value and may miss a brief peak.

| `-limit disk` | exit | sampled temporary high-water | peak RSS | user CPU | system CPU |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 64 MiB | 1 | 65,408,000 B (62.37 MiB) | 341,868,544 B (326.03 MiB) | 0.1481 s | 0.0480 s |
| 256 MiB | 1 | 268,172,800 B (255.70 MiB) | 318,586,880 B (303.83 MiB) | 0.2297 s | 0.1351 s |
| 440 MiB | 1 | 461,126,400 B (439.83 MiB) | 425,902,080 B (406.17 MiB) | 0.3235 s | 0.2609 s |
| 480 MiB | 1 | 500,371,200 B (477.26 MiB) | 460,865,536 B (439.52 MiB) | 0.3346 s | 0.2860 s |
| 488 MiB | 1 | 510,182,400 B (486.45 MiB) | 653,131,776 B (622.88 MiB) | 0.3327 s | 0.2123 s |
| 500 MiB | 1 | 519,993,600 B (495.94 MiB) | 477,167,616 B (455.06 MiB) | 0.3408 s | 0.2857 s |

## what the code accounts for

`SessionWorkspaceStore.reserveCompressedPreviewOutput` subtracts already-accounted session bytes and outstanding reservations from both the 512 MiB session cap and available volume space (while preserving the 64 MiB free-space floor). it reserves `maximumCacheBytes` and `maximumBytes` together. `ExperimentalImageMagickCompressor` passes the cache reservation to ImageMagick's `-limit disk`, writes stdout through an output-size cap, uses the reserved private cache directory, and validates the result. commit measures and removes the cache, verifies its configured cap and checks the GIF size again.

that accounting bounds the declared pixel cache and GIF output reservation when the pinned ImageMagick build honors these limits. it does not cap process RSS: ImageMagick's memory/map cache limits are resource selection thresholds, not a total process-memory limit. the audit also does not prove that delegates or other library allocations never create temporary files outside the reserved cache directory. verify those properties against the exact distributable build before app integration.

## limitations

- this is one 10-second synthetic profile on one arm64 machine and one non-release ImageMagick build; do not generalize to other dimensions, durations, builds, or hardware.
- all commands failed before producing output, so the audit does not establish successful output-size behavior or verify the output cap under load.
- 5 ms filesystem polling can undercount transient temporary-file peaks. process RSS and CPU came from `getrusage`, not `ps`; this sandbox denied `ps` access, and `/usr/bin/time -l` could not read `kern.clockrate` here.
- no app integration, user screen content, encoder comparison, visual review, or candidate-selection decision was part of this audit.
