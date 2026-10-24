import Foundation
import ImageIO

guard CommandLine.arguments.count >= 5,
  let framesPerSecond = Double(CommandLine.arguments[1]),
  framesPerSecond > 0
else {
  fputs("usage: imageio_encode fps output.gif frame.png...\n", stderr)
  exit(2)
}

let output = URL(fileURLWithPath: CommandLine.arguments[2])
let frames = CommandLine.arguments.dropFirst(3)
guard
  let destination = CGImageDestinationCreateWithURL(
    output as CFURL,
    "com.compuserve.gif" as CFString,
    frames.count,
    nil
  )
else {
  fputs("could not create GIF destination\n", stderr)
  exit(1)
}

CGImageDestinationSetProperties(
  destination,
  [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
)

for (index, path) in frames.enumerated() {
  let startCentiseconds = Int((Double(index) * 100 / framesPerSecond).rounded())
  let endCentiseconds = Int((Double(index + 1) * 100 / framesPerSecond).rounded())
  let delay = Double(max(1, endCentiseconds - startCentiseconds)) / 100
  let frameProperties =
    [
      kCGImagePropertyGIFDictionary: [
        kCGImagePropertyGIFDelayTime: delay,
        kCGImagePropertyGIFUnclampedDelayTime: delay,
      ]
    ] as CFDictionary
  let input = URL(fileURLWithPath: path)
  guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
  else {
    fputs("could not decode input frame: \(path)\n", stderr)
    exit(1)
  }
  CGImageDestinationAddImage(destination, image, frameProperties)
}

guard CGImageDestinationFinalize(destination) else {
  fputs("could not finalize GIF\n", stderr)
  exit(1)
}
