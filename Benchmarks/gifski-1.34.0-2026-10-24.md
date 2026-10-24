# gifski 1.34.0 benchmark

## result

this is a performance prototype comparing the official `gifski` 1.34.0 macOS release executable with the previously measured `ImageIOOriginalGIFEncoder` app helper. both paths completed one first-invocation run and seven warm runs for each of four synthetic 640×360, 240-frame, 24 fps profiles. every one of the 64 outputs passed the harness checks for dimensions, frame count, exact centisecond frame schedule, 10-second cumulative duration, and infinite looping.

| profile | path | first invocation | warm median | warm p90 | bytes |
| --- | --- | ---: | ---: | ---: | ---: |
| mixed | `gifski` | 0.8802 s | 0.8243 s | 0.8360 s | 1,745,722 |
| mixed | `imageio-app` | 1.0939 s | 0.9045 s | 0.9529 s | 2,595,223 |
| mostly-static-ui | `gifski` | 0.5388 s | 0.5579 s | 0.8165 s | 15,311 |
| mostly-static-ui | `imageio-app` | 0.7372 s | 0.7141 s | 0.7644 s | 11,815 |
| fast-scrolling | `gifski` | 0.7469 s | 0.8220 s | 1.0201 s | 909,046 |
| fast-scrolling | `imageio-app` | 0.9542 s | 0.9612 s | 1.6332 s | 874,638 |
| high-motion-gradient-cursor | `gifski` | 1.0177 s | 1.0200 s | 1.0572 s | 5,792,443 |
| high-motion-gradient-cursor | `imageio-app` | 1.1326 s | 1.1100 s | 1.1527 s | 11,174,716 |

the p90 uses nearest-rank over seven warm samples, so it is the maximum sample in each row. complete sample measurements and GIF metadata are retained in the ignored `Benchmarks/outputs/gifski-1.34.0-<profile>-20261024/raw.json` and `summary.json` directories on this benchmark machine. the runner sampled peak workspace size every 20 ms; because it removes temporary work immediately after each run, these readings are approximately the final output size and can miss brief intermediate files. peak resident memory and CPU user/system time were unavailable in this restricted environment. no visual comparison was performed; output size and structural validity do not establish visual quality.

these timings are not an equal-work performance comparison. the ImageIO app encoder validates the completed GIF by reopening it and inspecting every frame before returning; the Gifski CLI does not perform that app-level validation. the harness then runs its shared structural metadata parser on both outputs. therefore, the ImageIO-app path includes an additional per-frame validation pass in its timed interval, and the measured Gifski time omits the equivalent validation a future integrated Gifski path would need. also, Gifski's `--quality 90` has no equivalent setting in the ImageIO candidate, so these output-size and timing results are not an equal-quality comparison.

"first invocation" means the first measured process invocation for that path/profile. the run did not clear filesystem, PNG, or framework caches, so this is not a cache-cleared cold measurement. with seven warm samples, the nearest-rank p90 is the maximum observation and is sensitive to one outlier. compared with the earlier ImageIO-only report using the same helper and fixture checksums, current ImageIO medians changed by +0.9% for mixed, +1.4% for mostly-static-ui, +6.6% for fast-scrolling, and -1.3% for high-motion-gradient-cursor. the fast-scrolling ImageIO warm p90 is 1.6332 s here versus 0.9106 s previously (+79%), driven by one warm sample. this variability and the unequal validation work limit use of the observed deltas for an encoder decision.

the benchmark raw JSON has no wall-clock timestamp per sample. filesystem birth/last-modified times for the profile output directories place the runs at mixed 00:39:26–00:39:45 utc, mostly-static-ui 00:39:47–00:40:00 utc, fast-scrolling 00:40:00–00:40:18 utc, and high-motion-gradient-cursor 00:40:18–00:40:38 utc on 2026-10-24. a separate terminal/agent timeline places a Homebrew package installation at approximately 00:40–00:42 utc; it may have overlapped the end of mostly-static-ui and the fast-scrolling and high-motion runs. the integration owner also reported that a UI test build may have overlapped mixed, but its interval is unknown. these are possible background-activity confounds: there is no process trace to determine exact overlap or resource contention, and no impact adjustment was made. the separate ImageMagick encoding runs began around 00:44 utc, after the Gifski profiles had ended.

## release and executable provenance

- official release: [ImageOptim/gifski 1.34.0](https://github.com/ImageOptim/gifski/releases/tag/1.34.0), marked latest when checked on 2026-10-24. the tag resolves to signed commit `1060eab4500a20f27e2fa3ab7e85473d0e921cbd`.
- release asset: [`gifski-1.34.0.tar.xz`](https://github.com/ImageOptim/gifski/releases/download/1.34.0/gifski-1.34.0.tar.xz), official asset digest and locally verified SHA-256: `b9b6591aa163123d737353d9c8581efdf3234d28eeaa45329b31da905cd5a996`.
- extracted executable: `mac/gifski`; SHA-256: `f5f73e09fba870a21e8c502f3191e58633e5081b1914f71e32d5ee714450e839`.
- `file` identified a universal Mach-O binary; `lipo -archs` reported `x86_64 arm64`. the arm64 slice was executed natively on the reference Mac.
- `gifski --version` printed `gifski 1.34.0`.
- `otool -L` reported Apple system frameworks and `/usr/lib/libiconv.2.dylib` plus `/usr/lib/libSystem.B.dylib`; no non-system dynamic library was listed. the full tool metadata is in each raw run's `summary.json`.
- the downloaded asset was extracted under `/private/tmp/gifski-1.34.0`; it was not installed, bundled, or committed.

### CLI help output

captured from this executable with `--help`; terminal-only trailing spaces on blank lines are omitted.

```text
https://gif.ski by Kornel Lesiński

Usage: gifski [OPTIONS] --output <a.gif> <FILES>...

Arguments:
  <FILES>...
          one video file supported by FFmpeg, or multiple PNG image files

Options:
  -o, --output <a.gif>
          Destination file to write to; "-" means stdout

  -r, --fps <num>
          Frame rate of animation. If using PNG files as input, this means the speed, as all frames are kept.
          If video is used, it will be resampled to this constant rate by dropping and/or duplicating frames

          [default: 20]

      --fast-forward <x>
          Multiply speed of video by a factor

          [default: 1]

      --fast
          50% faster encoding, but 10% worse quality and larger file size

      --extra
          50% slower encoding, but 1% better quality and usually larger file size

  -Q, --quality <1-100>
          Lower quality may give smaller file

          [default: 90]

      --motion-quality <1-100>
          Lower values reduce motion

      --lossy-quality <1-100>
          Lower values introduce noise and streaks

  -W, --width <px>
          Maximum width.
          By default anims are limited to about 800x600

  -H, --height <px>
          Maximum height (stretches if the width is also set)

      --no-sort
          Use files exactly in the order given, rather than sorted

  -q, --quiet
          Do not display anything on standard output/console

      --repeat <num>
          Number of times the animation is repeated (-1 none, 0 forever or <value> repetitions)

      --bounce
          Make animation play forwards then backwards

      --fixed-color <RGBHEX>
          Always include this color in the palette

      --matte <RGBHEX>
          Background color for semitransparent pixels

      --y4m-color-override <bt709>
          The color space of the input YUV4MPEG2 video
          Possible values: bt709 fcc bt470bg bt601 smpte240 ycgco
          Defaults to bt709 for HD and bt601 for SD resolutions

  -h, --help
          Print help (see a summary with '-h')

  -V, --version
          Print version
```

## benchmark setup

- machine: the selected reference MacBook Air, Apple M2, 8 GB, arm64; macOS 27.0.1 build 26A434; Xcode 27.1 build 27A9275. AC power was connected and Low Power Mode was off. the model and memory are from the previously recorded reference-machine details; the sandbox blocked `sysctl -n hw.model` and `sysctl -n hw.memsize` during these runs.
- thermal status: `pmset -g therm` returned errors for thermal warning, performance warning, and CPU power telemetry. thermal state is unknown.
- benchmark branch base: `e321a5d2d129ac998727dd653e1fb207bea357fe` (`codex/gifski-benchmark`).
- ImageIO comparison: reused the prebuilt `imageio_app_encode` helper at `Benchmarks/outputs/imageio-app-mixed-20261024/tools/imageio_app_encode` from the existing mixed-profile measurement. its SHA-256 is `1f83577c9ca1e261b833991c650a3ad7db11cef189ab51146b6251456b22cfb5`; it is arm64 and links the system ImageIO/CoreGraphics/Foundation stack. its recorded compile inputs were `SessionWorkspaceStore.swift` SHA-256 `56dfbfe623aca502cc3242c8aa18b520934042db320db902ed84b647c9671106`, `OriginalGIFEncoder.swift` SHA-256 `d9f4e7b8e7282a90002a7dded7bd673239e85934ebc92d5d9ee8dfe0102e8aa1`, and `imageio_app_encode.swift` SHA-256 `a2f688642936036b08100da2e451680f6d675ec56c0e123016917919529ab9e9`. the later app preview change added an output inspector outside the encoding algorithm; this run intentionally reused the existing measured helper as requested.
- measurement: four profiles, two paths, one first invocation and seven warm runs per path. path order alternated between runs. each timer includes process launch, PNG decode, encode, the candidate's own work (including ImageIO's post-encode per-frame validation), the harness structural validation, and cleanup; helper compilation and fixture generation are excluded. caches were not cleared before the first measured invocation.
- fixture generation: seed 7, 640×360, 240 frames, 24 fps, 10 seconds. fixture manifests and combined PNG checksums:

| profile | manifest SHA-256 | frames SHA-256 |
| --- | --- | --- |
| mixed | `cd2a9ffb73a5908e221ae2fd0e28233b7a1ce426dee9f9b4239371c35b9c07e2` | `a2e07a4980e7b437bc1e44d6a9d8ff7f11c70126abaeeb9ad3a580ecd1143c9d` |
| mostly-static-ui | `6e2f785f8c29a9ca43cd1bbf91dd636e0405822c01438cb8a27ef1a7a35a28fa` | `d42ed02d552de0db283b9a2d720ac782b7b62dc8dd7c41817da0837b3ce71fc2` |
| fast-scrolling | `d31d28bcba4880b86dac358e81a87e466fe74631414db7e69528405338dc8eec` | `e0750bce46287c335993b3e2610505b0debe4f18fe7cfa25e700ff1cac850885` |
| high-motion-gradient-cursor | `8a90e5f8d09fe44045642bc1fb744d3865494ad8ede21e36b95ab06759f71c64` | `8436939cbc8b536dcc3ea3423669f4f0ccdda1dc14a75a3e5eee4b652b4c0c01` |

## exact invocation

the runner invoked `gifski` with this argument shape, expanding frames in ascending filename order from `frame_0000.png` through `frame_0239.png`:

```text
/private/tmp/gifski-1.34.0/mac/gifski --fps 24 --quality 90 --repeat 0 --no-sort -o <output.gif> <frame_0000.png> ... <frame_0239.png>
```

the ImageIO helper was invoked with its exact runner argument shape:

```text
<imageio_app_encode> 24 <output.gif> <frame_0000.png> ... <frame_0239.png>
```

the exact expanded argument arrays, timing, exit results, stderr/stdout, output metadata, and environment/tool records are in the raw JSON. invocation command for each profile, from the isolated worktree root, was:

```sh
PATH="/private/tmp/gifski-1.34.0/mac:$PATH" python3 Benchmarks/run_encoder_benchmark.py --fixture /Users/simaob/dev/gifferent/Benchmarks/generated/<profile>-640x360 --output Benchmarks/outputs/gifski-1.34.0-<profile>-20261024 --runs 7 --candidates gifski imageio-app --imageio-app-binary /Users/simaob/dev/gifferent/Benchmarks/outputs/imageio-app-mixed-20261024/tools/imageio_app_encode
```

## retained media and limits

each path produced byte-identical GIFs across all eight runs within a profile. after verifying the SHA-256 of each set, duplicate media files were removed and only the `first-invocation.gif` representative remains per path/profile. `raw.json` and `summary.json` remain intact in ignored output folders; no output binary or media was committed. retained GIF SHA-256 values:

| profile | path | SHA-256 |
| --- | --- | --- |
| mixed | `gifski` | `dfaa0b7866643a993cdea6ad1a5d5d91e760a3a1bef1cd07f04466b07ced35b9` |
| mixed | `imageio-app` | `37aa47e79bf02f91f83bf0bc92974b14ce745fc5636e24f1aa32ccd653abd36f` |
| mostly-static-ui | `gifski` | `3beeaabc6e18589bbb6c5b00cc5e1794a66a4d4ca7a65db2e9596a609064a555` |
| mostly-static-ui | `imageio-app` | `79cbf85089cb8b64530472b91b715dd51e90690b00203935a0a07777ef3f4970` |
| fast-scrolling | `gifski` | `597db1b092d1351c1b482160fefb36a85a128bc3aca4808feb7e8cd7bb1871a9` |
| fast-scrolling | `imageio-app` | `4194a5f956c9817af2bfa35a021aa346e20a70a713178752aa041f38c71476d8` |
| high-motion-gradient-cursor | `gifski` | `f4afa4f9e61d7b094cf6037f997c1a268b81fd85457a035a35032175f91efa1a` |
| high-motion-gradient-cursor | `imageio-app` | `48ed3ac05798146230ddfb80964d504819afdb0f3fb705f017fae88f3d642784` |

this result records offline PNG-to-GIF timings under the stated unequal-work conditions. it does not measure capture latency, stop-to-preview latency, full-app responsiveness, visual quality, or playback behavior in destination apps. the release executable's source build and dependency/license provenance are not audited by this run. the app's distribution candidate, bundled-source obligations, visual quality floor, and final encoder choice remain open gates. these measurements are insufficient on their own for a performance or encoder-selection decision. this report does not select an encoder or make a quality claim.
