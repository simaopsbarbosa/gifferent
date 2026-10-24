import CoreGraphics
import Darwin
import Foundation
import ImageIO
import XCTest

@testable import gifferent

final class ExperimentalImageMagickCompressorTests: XCTestCase {
  func testCompressionUsesAbsoluteExecutableArgumentsAndPreservesSourceMetadata() async throws {
    let fixture = try await makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let sourceBefore = try Data(contentsOf: fixture.source)
    let argumentsURL = fixture.directory.appendingPathComponent("arguments.txt")
    let executable = try fakeExecutable(
      in: fixture.directory,
      body: "printf '%s\\n' \"$@\" > '\(argumentsURL.path)'\ncat \"${15}\""
    )
    let destination = fixture.directory.appendingPathComponent("compressed.gif")
    let result = try await ExperimentalImageMagickCompressor().compress(
      fixture.source,
      executableURL: executable,
      scale: .seventyFivePercent,
      to: try makeReservation(fixture, destination: destination, maximumBytes: 100_000)
    )

    XCTAssertEqual(
      try String(contentsOf: argumentsURL, encoding: .utf8).components(separatedBy: "\n")
        .filter { !$0.isEmpty },
      [
        "-limit", "memory", "256MiB",
        "-limit", "map", "512MiB",
        "-limit", "disk", "4096",
        "-limit", "thread", "2",
        "-define",
        "registry:temporary-path=\(fixture.directory.appendingPathComponent("cache").path)",
        fixture.source.path,
        "-coalesce",
        "-resize",
        "75%",
        "-dither",
        "FloydSteinberg",
        "-define",
        "dither:diffusion-amount=35%",
        "-colors",
        "256",
        "-layers",
        "Optimize",
        "gif:-",
      ]
    )
    XCTAssertEqual(result.frameCount, fixture.metadata.frameCount)
    XCTAssertEqual(result.delaysCentiseconds, fixture.metadata.delaysCentiseconds)
    XCTAssertEqual(result.loopCount, fixture.metadata.loopCount)
    XCTAssertEqual(try Data(contentsOf: fixture.source), sourceBefore)
    XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
  }

  func testArgumentBuilderOmitsResizeAtOriginalScaleAndUsesRequestedDiffusionAmount() {
    XCTAssertEqual(
      ExperimentalImageMagickCompressor.arguments(
        sourceURL: URL(fileURLWithPath: "/tmp/source with spaces.gif"),
        scale: .original,
        diffusionAmount: 0,
        cacheDirectory: URL(fileURLWithPath: "/tmp/cache"),
        maximumCacheBytes: 12_345
      ),
      [
        "-limit", "memory", "256MiB",
        "-limit", "map", "512MiB",
        "-limit", "disk", "12345",
        "-limit", "thread", "2",
        "-define", "registry:temporary-path=/tmp/cache",
        "/tmp/source with spaces.gif",
        "-coalesce",
        "-dither", "FloydSteinberg",
        "-define", "dither:diffusion-amount=0%",
        "-colors", "256",
        "-layers", "Optimize",
        "gif:-",
      ]
    )
    XCTAssertEqual(ExperimentalImageMagickCompressor.defaultDiffusionAmount, 35)
  }

  func testInvalidDiffusionAmountDoesNotLaunchOrCreateOutput() async throws {
    let fixture = try await makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let marker = fixture.directory.appendingPathComponent("launched")
    let executable = try fakeExecutable(
      in: fixture.directory, body: ": > '\(marker.path)'\ncat \"$1\"")
    let destination = fixture.directory.appendingPathComponent("compressed.gif")

    do {
      _ = try await ExperimentalImageMagickCompressor().compress(
        fixture.source,
        executableURL: executable,
        scale: .original,
        diffusionAmount: 34,
        to: try makeReservation(fixture, destination: destination, maximumBytes: 100_000)
      )
      XCTFail("expected invalid diffusion amount")
    } catch let error as ExperimentalImageMagickCompressionError {
      XCTAssertEqual(error, .invalidDiffusionAmount)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
  }

  func testReservationCannotBeUsedWithAnUnaccountedSource() async throws {
    let fixture = try await makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let destination = fixture.directory.appendingPathComponent("compressed.gif")
    let reservation = try makeReservation(
      fixture,
      destination: destination,
      maximumBytes: 100_000
    )
    let externalSource = fixture.directory.appendingPathComponent("external.gif")

    do {
      _ = try await ExperimentalImageMagickCompressor().compress(
        externalSource,
        executableURL: URL(fileURLWithPath: "/usr/bin/false"),
        scale: .original,
        to: reservation
      )
      XCTFail("expected source mismatch")
    } catch let error as ExperimentalImageMagickCompressionError {
      XCTAssertEqual(error, .invalidSource)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
  }

  func testNonzeroExitIncludesBoundedStandardErrorAndRemovesTemporaryOutput() async throws {
    let fixture = try await makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let executable = try fakeExecutable(
      in: fixture.directory, body: "printf '%100000s' x >&2\nprintf x\nexit 7")
    let destination = fixture.directory.appendingPathComponent("compressed.gif")

    do {
      _ = try await ExperimentalImageMagickCompressor().compress(
        fixture.source,
        executableURL: executable,
        scale: .original,
        to: try makeReservation(fixture, destination: destination, maximumBytes: 100_000)
      )
      XCTFail("expected child failure")
    } catch let error as ExperimentalImageMagickCompressionError {
      guard case .processFailed(let status, let standardError) = error else {
        return XCTFail("unexpected error: \(error)")
      }
      XCTAssertEqual(status, 7)
      XCTAssertEqual(standardError.utf8.count, 64 * 1_024)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    XCTAssertEqual(try temporaryOutputFiles(in: fixture.directory), [])
  }

  func testOutputCapKillsProducerAndRemovesPartialFile() async throws {
    let fixture = try await makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let executable = try fakeExecutable(
      in: fixture.directory,
      body: "while :; do printf '%4096s' x; done"
    )
    let destination = fixture.directory.appendingPathComponent("compressed.gif")

    do {
      _ = try await ExperimentalImageMagickCompressor().compress(
        fixture.source,
        executableURL: executable,
        scale: .original,
        to: try makeReservation(fixture, destination: destination, maximumBytes: 128)
      )
      XCTFail("expected output cap")
    } catch let error as ExperimentalImageMagickCompressionError {
      XCTAssertEqual(error, .outputSizeExceeded)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    XCTAssertEqual(try temporaryOutputFiles(in: fixture.directory), [])
  }

  func testCancellationKillsChildAndRemovesPartialFile() async throws {
    let fixture = try await makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let marker = fixture.directory.appendingPathComponent("started")
    let executable = try fakeExecutable(
      in: fixture.directory,
      body: ": > '\(marker.path)'\nwhile :; do :; done"
    )
    let destination = fixture.directory.appendingPathComponent("compressed.gif")
    let reservation = try makeReservation(
      fixture, destination: destination, maximumBytes: 100_000
    )
    let task = Task {
      try await ExperimentalImageMagickCompressor().compress(
        fixture.source,
        executableURL: executable,
        scale: .original,
        to: reservation
      )
    }
    for _ in 0..<200 where !FileManager.default.fileExists(atPath: marker.path) {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("expected cancellation")
    } catch let error as ExperimentalImageMagickCompressionError {
      XCTAssertEqual(error, .cancelled)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    XCTAssertEqual(try temporaryOutputFiles(in: fixture.directory), [])
  }

  func testMetadataMismatchIsRejectedAndTemporaryOutputIsRemoved() async throws {
    let fixture = try await makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let mismatched = fixture.directory.appendingPathComponent("mismatch.gif")
    let oneFrame = try await makeGIF(directory: fixture.directory, frameColors: [[0, 0, 255, 255]])
    try FileManager.default.copyItem(at: oneFrame, to: mismatched)
    let executable = try fakeExecutable(in: fixture.directory, body: "cat '\(mismatched.path)'")
    let destination = fixture.directory.appendingPathComponent("compressed.gif")

    do {
      _ = try await ExperimentalImageMagickCompressor().compress(
        fixture.source,
        executableURL: executable,
        scale: .original,
        to: try makeReservation(fixture, destination: destination, maximumBytes: 100_000)
      )
      XCTFail("expected metadata mismatch")
    } catch let error as ExperimentalImageMagickCompressionError {
      XCTAssertEqual(error, .invalidOutput)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    XCTAssertEqual(try temporaryOutputFiles(in: fixture.directory), [])
  }

  func testInstalledImageMagickOptimizedDeltaFramesStayInsideLogicalCanvas() async throws {
    let executable = URL(fileURLWithPath: "/opt/homebrew/bin/magick")
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
      throw XCTSkip("install ImageMagick at /opt/homebrew/bin/magick to run this integration test")
    }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("gifferent-magick-delta-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let source = try await makeDeltaGIF(directory: directory)
    let encodedSource = try GIFMetadataInspector().inspect(source)
    let sourceMetadata = GIFAnimationMetadataSnapshot(
      frameCount: encodedSource.frameCount,
      delaysCentiseconds: encodedSource.delaysCentiseconds,
      loopCount: encodedSource.loopsForever ? 0 : nil
    )
    let destination = directory.appendingPathComponent("compressed.gif")
    let result = try await ExperimentalImageMagickCompressor().compress(
      source,
      executableURL: executable,
      scale: .original,
      to: try makeReservation(
        Fixture(directory: directory, source: source, metadata: sourceMetadata),
        destination: destination,
        maximumBytes: 10_000_000
      )
    )
    let frames = try GIFFrameDescriptorInspector.inspect(destination)

    XCTAssertEqual(result.width, 480)
    XCTAssertEqual(result.height, 270)
    XCTAssertEqual(result.frameCount, sourceMetadata.frameCount)
    XCTAssertEqual(result.delaysCentiseconds, sourceMetadata.delaysCentiseconds)
    XCTAssertEqual(result.loopCount, 0)
    XCTAssertEqual(frames.width, 480)
    XCTAssertEqual(frames.height, 270)
    XCTAssertEqual(frames.frames.count, result.frameCount)
    XCTAssertTrue(frames.frames.contains { $0.width < frames.width || $0.height < frames.height })
    XCTAssertTrue(
      frames.frames.allSatisfy {
        $0.left >= 0 && $0.top >= 0
          && $0.left + $0.width <= frames.width
          && $0.top + $0.height <= frames.height
      })
  }

  private struct Fixture {
    let directory: URL
    let source: URL
    let metadata: GIFAnimationMetadataSnapshot
  }

  private func makeReservation(
    _ fixture: Fixture,
    destination: URL,
    maximumBytes: Int64
  ) throws -> CompressedPreviewOutputReservation {
    let cacheDirectory = fixture.directory.appendingPathComponent("cache", isDirectory: true)
    try FileManager.default.createDirectory(
      at: cacheDirectory,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )
    return CompressedPreviewOutputReservation(
      url: destination,
      maximumBytes: maximumBytes,
      sourceURL: fixture.source,
      cacheDirectory: cacheDirectory,
      maximumCacheBytes: 4_096
    )
  }

  private struct GIFAnimationMetadataSnapshot {
    let frameCount: Int
    let delaysCentiseconds: [Int]
    let loopCount: Int?
  }

  private func makeFixture() async throws -> Fixture {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("gifferent-imagemagick-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let source = try await makeGIF(
      directory: directory,
      frameColors: [[255, 0, 0, 255], [0, 255, 0, 255]]
    )
    let metadata = try GIFMetadataInspector().inspect(source)
    let properties = try XCTUnwrap(
      CGImageSourceCopyProperties(
        XCTUnwrap(CGImageSourceCreateWithURL(source as CFURL, nil)), nil
      ) as? [CFString: Any]
    )
    let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] ?? [:]
    return Fixture(
      directory: directory,
      source: source,
      metadata: GIFAnimationMetadataSnapshot(
        frameCount: metadata.frameCount,
        delaysCentiseconds: metadata.delaysCentiseconds,
        loopCount: gif[kCGImagePropertyGIFLoopCount] as? Int
      )
    )
  }

  private func makeGIF(directory: URL, frameColors: [[UInt8]]) async throws -> URL {
    var frames: [CapturedPNGFrame] = []
    for (index, color) in frameColors.enumerated() {
      let frameURL = directory.appendingPathComponent("frame-\(UUID().uuidString).png")
      try png(color: color).write(to: frameURL)
      frames.append(CapturedPNGFrame(url: frameURL, timestamp: Double(index) * 0.05))
    }
    let output = directory.appendingPathComponent("source-\(UUID().uuidString).gif")
    _ = try await ImageIOOriginalGIFEncoder().encode(
      CapturedPNGSequence(frames: frames), loopMode: .forever,
      to: PreviewOutputReservation(url: output, maximumBytes: 100_000)
    )
    return output
  }

  private func makeDeltaGIF(directory: URL) async throws -> URL {
    let width = 480
    let height = 270
    let firstURL = directory.appendingPathComponent("delta-base.png")
    let secondURL = directory.appendingPathComponent("delta-change.png")
    try png(width: width, height: height, changed: false).write(to: firstURL)
    try png(width: width, height: height, changed: true).write(to: secondURL)
    let output = directory.appendingPathComponent("delta-source.gif")
    _ = try await ImageIOOriginalGIFEncoder().encode(
      CapturedPNGSequence(frames: [
        CapturedPNGFrame(url: firstURL, timestamp: 0),
        CapturedPNGFrame(url: secondURL, timestamp: 0.05),
      ]),
      loopMode: .forever,
      to: PreviewOutputReservation(url: output, maximumBytes: 10_000_000)
    )
    return output
  }

  private func png(color: [UInt8]) throws -> Data {
    try PNGFrameEncoder().encode(
      RecordingFrame(
        timestampNanoseconds: 1,
        width: 2,
        height: 2,
        bytesPerRow: 8,
        bgra: Data([
          color[2], color[1], color[0], color[3], color[2], color[1], color[0], color[3],
          color[2], color[1], color[0], color[3], color[2], color[1], color[0], color[3],
        ])
      )
    )
  }

  private func png(width: Int, height: Int, changed: Bool) throws -> Data {
    var bgra = Data(repeating: 0, count: width * height * 4)
    for pixel in 0..<(width * height) {
      bgra[pixel * 4 + 3] = 255
    }
    if changed {
      for y in 120..<140 {
        for x in 230..<250 {
          let offset = (y * width + x) * 4
          bgra[offset] = 255
          bgra[offset + 1] = 255
          bgra[offset + 2] = 255
        }
      }
    }
    return try PNGFrameEncoder().encode(
      RecordingFrame(
        timestampNanoseconds: 1,
        width: width,
        height: height,
        bytesPerRow: width * 4,
        bgra: bgra
      )
    )
  }

  private func fakeExecutable(in directory: URL, body: String) throws -> URL {
    let executable = directory.appendingPathComponent("fake-magick-\(UUID().uuidString)")
    try Data(("#!/bin/sh\nset -eu\n" + body + "\n").utf8).write(to: executable)
    guard chmod(executable.path, 0o700) == 0 else {
      throw NSError(domain: "test", code: Int(errno))
    }
    return executable
  }

  private func temporaryOutputFiles(in directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path)
      .filter { $0.hasPrefix(".gifferent-compress-") }
  }
}
