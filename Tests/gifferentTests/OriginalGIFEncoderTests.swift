import CoreGraphics
import Foundation
import ImageIO
import XCTest

@testable import gifferent

final class OriginalGIFEncoderTests: XCTestCase {
  func testEncodesLoopingGIFAndValidatesPerFrameSchedule() async throws {
    let directory = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let first = directory.appendingPathComponent("one.png")
    let second = directory.appendingPathComponent("two.png")
    try png(color: [255, 0, 0, 255]).write(to: first)
    try png(color: [0, 255, 0, 255]).write(to: second)
    let output = directory.appendingPathComponent("preview.gif")
    let sequence = CapturedPNGSequence(frames: [
      CapturedPNGFrame(url: first, timestamp: 10),
      CapturedPNGFrame(url: second, timestamp: 10.02),
    ])

    let result = try await ImageIOOriginalGIFEncoder().encode(
      sequence,
      to: PreviewOutputReservation(url: output, maximumBytes: 10_000)
    )
    XCTAssertEqual(result.width, 1)
    XCTAssertEqual(result.height, 1)
    XCTAssertEqual(result.frameCount, 2)
    XCTAssertEqual(result.delaysCentiseconds, [2, 2])
    XCTAssertEqual(result.durationCentiseconds, 4)
    XCTAssertTrue(result.loopsForever)
    XCTAssertGreaterThan(result.fileBytes, 0)
    XCTAssertTrue(
      try GIFLoopExtensionParser.containsLoopingApplicationExtension(
        in: Data(contentsOf: output)
      )
    )
  }

  func testOnceModeOmitsLoopExtensionAndMetadataReportsFinitePlayback() async throws {
    let directory = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let frame = directory.appendingPathComponent("frame.png")
    try png(color: [255, 0, 0, 255]).write(to: frame)
    let output = directory.appendingPathComponent("once.gif")
    let result = try await ImageIOOriginalGIFEncoder().encode(
      CapturedPNGSequence(frames: [CapturedPNGFrame(url: frame, timestamp: 0)]),
      loopMode: .once,
      to: PreviewOutputReservation(url: output, maximumBytes: 10_000)
    )

    XCTAssertFalse(result.loopsForever)
    XCTAssertEqual(try GIFMetadataInspector().inspect(output), result)
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
    let properties = try XCTUnwrap(
      CGImageSourceCopyProperties(source, nil) as? [CFString: Any])
    let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] ?? [:]
    let loopCount = gifProperties[kCGImagePropertyGIFLoopCount] as? Int
    XCTAssertTrue(loopCount == nil || loopCount == 1)
    XCTAssertFalse(
      try GIFLoopExtensionParser.containsLoopingApplicationExtension(
        in: Data(contentsOf: output)
      )
    )
  }

  func testGIFLoopExtensionParserMatchesIdentifiersOnlyInApplicationExtensions() throws {
    let netscapeGIF = minimalGIF(
      extension: applicationExtension(identifier: "NETSCAPE2.0", data: [0x01, 0x00, 0x00])
    )
    let animationExtensionsGIF = minimalGIF(
      extension: applicationExtension(identifier: "ANIMEXTS1.0", data: [0x01, 0x00, 0x00])
    )
    let commentWithIdentifier = minimalGIF(
      extension: Data([0x21, 0xFE, 0x0B]) + Data("NETSCAPE2.0".utf8) + Data([0x00])
    )

    XCTAssertTrue(try GIFLoopExtensionParser.containsLoopingApplicationExtension(in: netscapeGIF))
    XCTAssertTrue(
      try GIFLoopExtensionParser.containsLoopingApplicationExtension(in: animationExtensionsGIF)
    )
    XCTAssertFalse(
      try GIFLoopExtensionParser.containsLoopingApplicationExtension(in: commentWithIdentifier)
    )
  }

  func testGIFLoopExtensionParserRejectsTruncatedBlocks() {
    let truncatedApplicationExtension = minimalGIF(
      extension: Data([0x21, 0xFF, 0x0B]) + Data("NETS".utf8)
    )
    let truncatedImageData = minimalGIF(extension: nil).dropLast(2)

    XCTAssertThrowsError(
      try GIFLoopExtensionParser.containsLoopingApplicationExtension(
        in: truncatedApplicationExtension
      )
    )
    XCTAssertThrowsError(
      try GIFLoopExtensionParser.containsLoopingApplicationExtension(in: Data(truncatedImageData))
    )
  }

  func testCumulativeRoundingPreservesDurationForRegularAndIrregularTimestamps() throws {
    XCTAssertEqual(
      try ImageIOOriginalGIFEncoder.frameDelaysCentiseconds(
        for: (0..<6).map { Double($0) / 24 }
      ),
      [4, 4, 5, 4, 4, 4]
    )
    XCTAssertEqual(
      try ImageIOOriginalGIFEncoder.frameDelaysCentiseconds(for: [1, 1.015, 1.050]),
      [2, 3, 4]
    )
    XCTAssertEqual(
      try ImageIOOriginalGIFEncoder.frameDelaysCentiseconds(for: [7]),
      [4]
    )
  }

  func testMalformedAndMissingFramesRemovePartialOutput() async throws {
    let directory = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let badFrame = directory.appendingPathComponent("bad.png")
    try Data("not a png".utf8).write(to: badFrame)
    let missingFrame = directory.appendingPathComponent("missing.png")

    for url in [badFrame, missingFrame] {
      let output = directory.appendingPathComponent(UUID().uuidString + ".gif")
      do {
        _ = try await ImageIOOriginalGIFEncoder().encode(
          CapturedPNGSequence(frames: [CapturedPNGFrame(url: url, timestamp: 0)]),
          to: PreviewOutputReservation(url: output, maximumBytes: 10_000)
        )
        XCTFail("expected invalid frame")
      } catch let error as OriginalGIFEncodingError {
        XCTAssertEqual(error, .invalidFrame)
      }
      XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
  }

  func testOutputLimitRemovesOversizeGIF() async throws {
    let directory = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let frame = directory.appendingPathComponent("frame.png")
    try png(color: [12, 34, 56, 255]).write(to: frame)
    let output = directory.appendingPathComponent("preview.gif")

    do {
      _ = try await ImageIOOriginalGIFEncoder().encode(
        CapturedPNGSequence(frames: [CapturedPNGFrame(url: frame, timestamp: 0)]),
        to: PreviewOutputReservation(url: output, maximumBytes: 1)
      )
      XCTFail("expected size limit")
    } catch let error as OriginalGIFEncodingError {
      XCTAssertEqual(error, .outputSizeExceeded)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
  }

  func testCancellationRemovesPartialGIF() async throws {
    let directory = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let first = directory.appendingPathComponent("one.png")
    let second = directory.appendingPathComponent("two.png")
    try png(color: [255, 0, 0, 255]).write(to: first)
    try png(color: [0, 255, 0, 255]).write(to: second)
    let output = directory.appendingPathComponent("preview.gif")
    let firstFrameAdded = DispatchSemaphore(value: 0)
    let continueEncoding = DispatchSemaphore(value: 0)
    let encoder = ImageIOOriginalGIFEncoder { count in
      if count == 1 {
        firstFrameAdded.signal()
        _ = continueEncoding.wait(timeout: .now() + 5)
      }
    }
    let task = Task {
      try await encoder.encode(
        CapturedPNGSequence(frames: [
          CapturedPNGFrame(url: first, timestamp: 0),
          CapturedPNGFrame(url: second, timestamp: 0.04),
        ]),
        to: PreviewOutputReservation(url: output, maximumBytes: 10_000)
      )
    }
    XCTAssertEqual(firstFrameAdded.wait(timeout: .now() + 5), .success)
    task.cancel()
    continueEncoding.signal()
    do {
      _ = try await task.value
      XCTFail("expected cancellation")
    } catch let error as OriginalGIFEncodingError {
      XCTAssertEqual(error, .cancelled)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
  }

  func testEditedGIFPreservesTrimmedFrameContentSpeedAndLoopThroughEncoding() async throws {
    let directory = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let colors: [[UInt8]] = [
      [255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255],
      [255, 255, 0, 255], [255, 0, 255, 255],
    ]
    let frames = try colors.enumerated().map { index, color in
      let url = directory.appendingPathComponent("source-\(index).png")
      try png(color: color).write(to: url)
      return CapturedPNGFrame(url: url, timestamp: Double(index) * 0.04)
    }
    let source = CapturedPNGSequence(frames: frames)
    let ranges = [0..<5, 1..<4, 4..<5]
    for range in ranges {
      for speed in [0.5, 1.0, 2.0] {
        for loopMode in [GIFLoopMode.once, .forever] {
          let edited = try GIFEditModel.apply(
            GIFEditParameters(
              frameRange: GIFFrameRange(
                startIndex: range.lowerBound, endIndexExclusive: range.upperBound),
              playbackSpeed: speed, loopMode: loopMode), to: source)
          let output = directory.appendingPathComponent(UUID().uuidString + ".gif")
          let result = try await ImageIOOriginalGIFEncoder().encode(
            edited.sequence, loopMode: edited.loopMode,
            to: PreviewOutputReservation(url: output, maximumBytes: 10_000))
          let expectedDelay = Int(4 / speed)
          XCTAssertEqual(result.frameCount, range.count)
          XCTAssertEqual(
            result.delaysCentiseconds, Array(repeating: expectedDelay, count: range.count))
          XCTAssertEqual(result.durationCentiseconds, expectedDelay * range.count)
          XCTAssertEqual(result.loopsForever, loopMode == .forever)
          XCTAssertEqual(result.width, 1)
          XCTAssertEqual(result.height, 1)
          let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
          for (outputIndex, sourceIndex) in range.enumerated() {
            let image = try XCTUnwrap(
              CGImageSourceCreateImageAtIndex(imageSource, outputIndex, nil))
            XCTAssertEqual(try rgbaPixel(image), colors[sourceIndex], "frame order/content changed")
          }
        }
      }
    }
  }

  func testTrimmedIrregularSequenceKeepsLastSelectedFramesOwnDuration() async throws {
    let directory = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let frame = directory.appendingPathComponent("frame.png")
    try png(color: [255, 0, 0, 255]).write(to: frame)
    let source = CapturedPNGSequence(
      frames: [0.0, 0.02, 0.07, 0.15].map {
        CapturedPNGFrame(url: frame, timestamp: $0)
      })
    for (range, expectedDelays) in [(1..<3, [5, 8]), (2..<3, [8]), (3..<4, [8])] {
      let edited = try GIFEditModel.apply(
        GIFEditParameters(
          frameRange: GIFFrameRange(
            startIndex: range.lowerBound, endIndexExclusive: range.upperBound),
          playbackSpeed: 1, loopMode: .once), to: source)
      let result = try await ImageIOOriginalGIFEncoder().encode(
        edited.sequence, loopMode: edited.loopMode,
        to: PreviewOutputReservation(
          url: directory.appendingPathComponent(UUID().uuidString + ".gif"), maximumBytes: 10_000))
      XCTAssertEqual(result.delaysCentiseconds, expectedDelays)
      XCTAssertEqual(result.durationCentiseconds, expectedDelays.reduce(0, +))
    }
  }

  private func rgbaPixel(_ image: CGImage) throws -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: 4)
    try bytes.withUnsafeMutableBytes { storage in
      let context = try XCTUnwrap(
        CGContext(
          data: storage.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
          bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    return bytes
  }

  private func png(color: [UInt8]) throws -> Data {
    let frame = RecordingFrame(
      timestampNanoseconds: 1,
      width: 1,
      height: 1,
      bytesPerRow: 4,
      bgra: Data([color[2], color[1], color[0], color[3]])
    )
    return try PNGFrameEncoder().encode(frame)
  }

  private func applicationExtension(identifier: String, data: [UInt8]) -> Data {
    Data([0x21, 0xFF, 0x0B]) + Data(identifier.utf8) + Data([UInt8(data.count)]) + Data(data)
      + Data([0x00])
  }

  private func minimalGIF(extension extensionData: Data?) -> Data {
    var bytes = Data("GIF89a".utf8)
    bytes.append(contentsOf: [0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00])
    if let extensionData { bytes.append(extensionData) }
    bytes.append(contentsOf: [
      0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
      0x02, 0x01, 0x4C, 0x00, 0x3B,
    ])
    return bytes
  }

  private func uniqueTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
  }
}
