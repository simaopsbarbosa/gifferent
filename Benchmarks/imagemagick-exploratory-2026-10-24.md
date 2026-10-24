# imagemagick exploratory benchmark — 2026-10-24

## status

this is a partial, exploratory Homebrew comparison. it does not select or promote an encoder, establish a speed claim, or establish visual quality. two of four profiles completed; the fast-scrolling attempt stopped when the filesystem ran out of space while the harness tried to write `raw.json`. the high-motion profile was not started. no existing benchmark outputs were removed.

each completed profile ran one first invocation and seven warm samples for `magick`, `magick-unoptimized`, and the prebuilt `ImageIOOriginalGIFEncoder` helper (`imageio-app`). all 24 outputs per profile passed the harness checks for GIF structure, 640×360 dimensions, 240 frames, the expected per-frame centisecond delay schedule, 10-second duration, and infinite looping. the harness confirms metadata validity only; this report makes no visual-fidelity or playback claim.

## measurements

times are offline PNG-to-GIF processing, not capture or stop-to-preview latency. the p90 is the harness's nearest-rank percentile over seven warm runs. all samples for a candidate/profile had the same output size.

| profile | path | warm median | warm p90 | first invocation | output bytes |
| --- | --- | ---: | ---: | ---: | ---: |
| mixed | `magick` | 14.6536 s | 14.8948 s | 20.6968 s | 9,453,925 |
| mixed | `magick-unoptimized` | 5.6490 s | 5.7830 s | 5.6840 s | 8,370,417 |
| mixed | `imageio-app` | 0.9049 s | 0.9291 s | 1.0305 s | 2,595,223 |
| mostly-static-ui | `magick` | 26.1608 s | 27.2713 s | 26.0343 s | 14,094 |
| mostly-static-ui | `magick-unoptimized` | 4.3901 s | 4.6873 s | 4.5490 s | 1,152,138 |
| mostly-static-ui | `imageio-app` | 0.7062 s | 0.7432 s | 0.7013 s | 11,815 |

peak resident memory was unavailable for every sample. peak temporary workspace samples equaled each output GIF's size, because the harness polls the workspace every 20 ms and misses short-lived activity. cpu user/system measurements were unavailable. the numbers above should not be used to select a release path.

## host and timing limits

- machine: the project reference is the architect-approved MacBook Air with M2 and 8 GB. these runs used arm64 macOS 27.0.1 build 26A434 and Xcode 27.1 build 27A9275. `sysctl` could not read the model, chip string, or memory in this sandbox, so those values come from the approved benchmark environment, not this run's probe.
- power: on AC; Low Power Mode off. `pmset -g therm` returned no thermal warning or CPU power telemetry, so thermal state is unknown.
- contention: an Xcode UI test build overlapped an ImageMagick encoding run; its exact interval and load are unknown. timings are exploratory and confounded. the Homebrew installation itself occurred around 00:40–00:42 UTC; ImageMagick profile measurements began at 00:44:01 UTC and 00:48:27 UTC.
- the earlier ImageIO app benchmark is a separate run. within this run, ImageIO was measured alongside each ImageMagick path, but shared-machine load was not controlled.
- benchmark base revision: `e321a5d2d129ac998727dd653e1fb207bea357fe`.

## exploratory Homebrew build

ImageMagick was installed with `brew install imagemagick` for this benchmark only. it was not bundled with the app. the formula installed ImageMagick 7.1.2-34 and its missing dependency closure (`libheif` 1.23.6 and `libde265` 1.1.3). Homebrew also upgraded existing formulae during installation: `libpng` 1.6.58→1.6.59, `freetype` 2.14.3→2.15.0, `libvmaf` 3.2.0→3.2.1, and `aom` 3.14.1→3.15.2. Homebrew fetched a `brotli` 1.2.1 bottle but left the installed version at 1.2.0. this state change is recorded; no package was rolled back. no `imagemagick-full` formula was installed.

the `magick` executable reports ImageMagick 7.1.2-34, Q16-HDRI, arm64, upstream revision `c5d4ca8a0:20261014`, clang 21.0.0, and features `Cipher DPC HDRI Modules`. built-in delegates include `bzlib freetype heic jng jpeg lcms ltdl lzma png tiff webp xml zlib zstd`. GIF reports read/write support. the executable SHA-256 is `324c185d0dead1cf7326e7f87743da28086dde0a00538b96d5cd320ed7543466`. the reused prebuilt `imageio-app` helper SHA-256 is `1f83577c9ca1e261b833991c650a3ad7db11cef189ab51146b6251456b22cfb5`; it was not rebuilt for this run.

relevant configure flags include `--enable-osx-universal-binary=no`, `--disable-opencl`, `--enable-shared`, `--enable-static`, `--with-modules`, `--with-webp=yes`, `--with-heic=yes`, `--with-raw=no`, `--without-djvu`, `--without-fftw`, `--without-pango`, `--without-wmf`, `--without-jxl`, `--without-openexr`, `--without-x`, and `--disable-debug`. quantum depth is 16; channel-mask depth is 32. `magick -list configure` reports `SECURITY_POLICY open`. `magick -list policy` found the formula's `policy.xml` with undefined policy rights plus the built-in policy entry; this is not a restrictive runtime policy.

`otool -L` on `magick` reports direct dependencies on ImageMagick's `libMagickCore` and `libMagickWand`, Homebrew `liblcms2`, `libfreetype`, `libltdl`, and system `libxml2`, `libbz2`, `libz`, `libSystem`, and `libc++`. this is not a complete dependency or license inventory: dynamically loaded coder modules and their transitive libraries need separate review for any real bundle.

the formula's direct required dependencies were freetype 2.15.0, jpeg-turbo 3.2.0, libheif 1.23.6, libpng 1.6.59, libtiff 4.7.2, libtool 2.6.2, little-cms2 2.19.1, webp 1.6.0, and xz 5.8.4. transitive dependencies and their license obligations were not audited here.

the run used `-dither FloydSteinberg -define dither:diffusion-amount=100% -colors 256`; the optimized path also used `-layers Optimize`, and both set `-loop 0`. the exact argument arrays for every successful run remain in `raw.json`. each timed run includes helper process launch, PNG decode, encoding, output validation, and cleanup; fixture generation and the already-built helper are excluded.

## artifacts and cleanup

the raw records, summaries, and representative GIFs are under ignored `Benchmarks/outputs/` paths on the benchmark machine:

- `magick-mixed-20261024/`
- `magick-mostly-static-ui-20261024/`
- `magick-fast-scrolling-20261024/` contains only an empty `raw.json` placeholder and temporary tool metadata from the failed attempt; it contains no successful runs or GIFs.

for each completed profile and each of the three paths, the eight GIFs had one identical SHA-256. after checksum verification, seven duplicates were removed and `warm-01.gif` was retained. raw JSON still records all eight successful samples. retained outputs:

| profile | path | sha-256 | bytes |
| --- | --- | --- | ---: |
| mixed | `magick` | `9b2b9d2197119b0ce48566192c5f891d2bade6d419b7de4e41050445b0c16a79` | 9,453,925 |
| mixed | `magick-unoptimized` | `c02fd9d10f00064580c3b744a5fbee75e5a8922217b8aac30a984f54c1bf00ef` | 8,370,417 |
| mixed | `imageio-app` | `37aa47e79bf02f91f83bf0bc92974b14ce745fc5636e24f1aa32ccd653abd36f` | 2,595,223 |
| mostly-static-ui | `magick` | `04486d8e9bed37a41e7c5427b40edc7187bb55fbfd63e50c0926a50c8dbe4f3f` | 14,094 |
| mostly-static-ui | `magick-unoptimized` | `827fa40e6eb707f4da991e3a94c52ae0516d390acc807b3cd74ef8691c2eee8d` | 1,152,138 |
| mostly-static-ui | `imageio-app` | `79cbf85089cb8b64530472b91b715dd51e90690b00203935a0a07777ef3f4970` | 11,815 |

the fast-scrolling attempt failed with `OSError: [Errno 28] No space left on device` while writing `raw.json`; the harness had no completed result to record. free disk space was 254 MiB after the failed attempt. the high-motion profile was not attempted. all benchmark output paths are ignored; no pre-existing benchmark output was deleted.

## commands

completed profile commands, from the isolated worktree root:

```sh
python3 Benchmarks/run_encoder_benchmark.py --fixture /Users/simaob/dev/gifferent/Benchmarks/generated/mixed-640x360 --output Benchmarks/outputs/magick-mixed-20261024 --runs 7 --candidates magick magick-unoptimized imageio-app --imageio-app-binary /Users/simaob/dev/gifferent/Benchmarks/outputs/imageio-app-mixed-20261024/tools/imageio_app_encode
python3 Benchmarks/run_encoder_benchmark.py --fixture /Users/simaob/dev/gifferent/Benchmarks/generated/mostly-static-ui-640x360 --output Benchmarks/outputs/magick-mostly-static-ui-20261024 --runs 7 --candidates magick magick-unoptimized imageio-app --imageio-app-binary /Users/simaob/dev/gifferent/Benchmarks/outputs/imageio-app-mixed-20261024/tools/imageio_app_encode
python3 Benchmarks/run_encoder_benchmark.py --fixture /Users/simaob/dev/gifferent/Benchmarks/generated/fast-scrolling-640x360 --output Benchmarks/outputs/magick-fast-scrolling-20261024 --runs 7 --candidates magick magick-unoptimized imageio-app --imageio-app-binary /Users/simaob/dev/gifferent/Benchmarks/outputs/imageio-app-mixed-20261024/tools/imageio_app_encode
```

the third command is recorded for the failed attempt; it did not complete a sample. `python3 -m unittest discover -s Benchmarks -p 'test_encoder_benchmark.py' -v` passed all 28 benchmark harness tests before the runs.

## source and license references

- [Homebrew imagemagick formula](https://formulae.brew.sh/formula/imagemagick) and [formula source](https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/i/imagemagick.rb) document the package version and formula dependencies.
- [ImageMagick upstream](https://imagemagick.org/), [command-line options](https://imagemagick.org/command-line-options/), [security policy](https://imagemagick.org/security-policy/), and [license](https://imagemagick.org/license/) are the official project references. the upstream options document the layer optimization and dither controls used here.
- the official [ImageMagick license](https://imagemagick.org/license/) requires a license copy and clear attribution when ImageMagick is redistributed. this benchmark does not evaluate the Homebrew bundle or its dependencies for product distribution.

