import CoreGraphics
import Foundation
import ImageIO
import XCTest

@testable import gifferent

final class PNGFrameEncoderTests: XCTestCase {
  func testEncodesBGRAFrameAsPNGWithSamePixels() throws {
    let source = RecordingFrame(
      timestampNanoseconds: 1,
      width: 2,
      height: 1,
      bytesPerRow: 8,
      bgra: Data([0, 0, 255, 255, 0, 255, 0, 255])
    )

    let png = try PNGFrameEncoder().encode(source)
    let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
    XCTAssertEqual(image.width, 2)
    XCTAssertEqual(image.height, 1)

    let colors = try decodedPixels(image)
    XCTAssertEqual(colors, [255, 0, 0, 255, 0, 255, 0, 255])
  }

  func testRejectsInvalidDimensionsAndTruncatedBytes() {
    let badFrames = [
      RecordingFrame(
        timestampNanoseconds: 1, width: 0, height: 1, bytesPerRow: 4,
        bgra: Data([0, 0, 0, 255])),
      RecordingFrame(
        timestampNanoseconds: 1, width: 2, height: 1, bytesPerRow: 4,
        bgra: Data([0, 0, 0, 255])),
      RecordingFrame(
        timestampNanoseconds: 1, width: 1, height: 2, bytesPerRow: 4,
        bgra: Data([0, 0, 0, 255])),
    ]
    for frame in badFrames {
      XCTAssertThrowsError(try PNGFrameEncoder().encode(frame)) { error in
        XCTAssertEqual(error as? PNGFrameEncodingError, .invalidFrame)
      }
    }
  }

  private func decodedPixels(_ image: CGImage) throws -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    let context = try XCTUnwrap(
      CGContext(
        data: &pixels,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: image.width * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
      ))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return pixels
  }
}
