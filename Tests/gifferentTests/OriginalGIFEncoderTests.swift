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

  private func uniqueTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
  }
}
