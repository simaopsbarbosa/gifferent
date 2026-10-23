import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PNGFrameEncodingError: Error, Equatable {
  case invalidFrame
  case imageCreationFailed
  case destinationCreationFailed
  case encodingFailed
}

struct PNGFrameEncoder {
  func encode(_ frame: RecordingFrame) throws -> Data {
    guard frame.width > 0, frame.height > 0,
      frame.width <= Int.max / 4,
      frame.bytesPerRow >= frame.width * 4,
      frame.height <= Int.max / frame.bytesPerRow,
      frame.bgra.count == frame.bytesPerRow * frame.height
    else { throw PNGFrameEncodingError.invalidFrame }

    guard let provider = CGDataProvider(data: frame.bgra as CFData),
      let image = CGImage(
        width: frame.width,
        height: frame.height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: frame.bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Little.union(
          CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
      )
    else { throw PNGFrameEncodingError.imageCreationFailed }

    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output, UTType.png.identifier as CFString, 1, nil
      )
    else { throw PNGFrameEncodingError.destinationCreationFailed }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw PNGFrameEncodingError.encodingFailed
    }
    return output as Data
  }
}
