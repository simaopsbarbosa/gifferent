# clipboard copy comparison · 2026-11-03

this measures the actual image and file clipboard adapters against the same two previously generated quality-90 GIFs. there is no encoding change. every measured copy retained byte-identical content and the same 240 frames; no new visual-quality judgment is needed for the copied bytes. this does not prove browser upload or animation behavior.

## environment and method

ProductName:		macOS; ProductVersion:		27.0.1; BuildVersion:		26A434; ; Mac14,2; Xcode 27.1; Build version 27A9275; .

Now drawing from 'AC Power';  -InternalBattery-0 (id=36175971)	100%; charged; 0:00 remaining present: true;  low power mode is off. both modes alternate order on this machine, using fresh processes and private named pasteboards, with one first run plus seven measured warm runs per fixture/mode. file warm runs seed an existing attachment to exercise atomic replacement. p90 uses nearest rank, the largest of seven warm samples. timings include the adapter's file read/copy and pasteboard publication; validation runs after the timer. process peak RSS from `/usr/bin/time -l` includes validation and ImageIO readback, and excludes the pasteboard service and any browser. file copy may use APFS cloning, so these are local measurements rather than a general disk-throughput claim.

| fixture | mode | GIF bytes | median ms | p90 ms | max process RSS mib |
| --- | --- | ---: | ---: | ---: | ---: |
| mostly-static-ui-quality-90 | image | 15311 | 1.315 | 3.485 | 17.08 |
| mostly-static-ui-quality-90 | file | 15311 | 4.042 | 6.980 | 18.38 |
| high-motion-gradient-cursor-quality-90 | image | 5792443 | 2.892 | 4.543 | 29.78 |
| high-motion-gradient-cursor-quality-90 | file | 5792443 | 4.183 | 7.535 | 29.61 |

file copy retains one attachment of at most 512 mib outside the recording workspace. atomic replacement can temporarily add another 512 mib; staging is removed after success/failure/cancellation. these fixtures retained 15,311 and 5,792,443 bytes respectively, with no increase in encoded output size.

## reproduction and limits

```sh
xcrun swiftc -swift-version 6 -parse-as-library Sources/App/GIFClipboard.swift Benchmarks/clipboard-copy.swift -o /private/tmp/gifferent-clipboard-copy-benchmark
/usr/bin/time -l /private/tmp/gifferent-clipboard-copy-benchmark image Benchmarks/reviews/gifski-quality-sweep-2026-10-24/gifs/high-motion-gradient-cursor-quality-90.gif /private/tmp/gifferent-clipboard-benchmark-cache
/usr/bin/time -l /private/tmp/gifferent-clipboard-copy-benchmark file Benchmarks/reviews/gifski-quality-sweep-2026-10-24/gifs/high-motion-gradient-cursor-quality-90.gif /private/tmp/gifferent-clipboard-benchmark-cache
```

the helper writes only named pasteboards and the explicit cache argument; it does not replace the user's clipboard. the standalone helper emitted sandbox-extension warnings for file URL pasteboard access, but readback and byte/animation checks succeeded. actual app-to-browser compatibility still needs real-Mac verification. raw measurements, source hashes, and cold samples are in [the result JSON](results/clipboard-copy-2026-11-03.json). this is a clipboard-path comparison, not a new capture/encoding benchmark or release acceptance.
