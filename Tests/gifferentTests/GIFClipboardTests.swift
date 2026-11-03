import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import gifferent

@MainActor
final class GIFClipboardTests: XCTestCase {
  func testFileCopyRetainsAnimatedBytesAfterSourceCleanupAndStoreRecreation() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("session/preview.gif")
    let bytes = try animatedGIF(at: source)
    let directory = root.appendingPathComponent("clipboard")
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let writer = NSPasteboardGIFFileWriter(
      pasteboard: pasteboard, store: GIFClipboardFileStore(directory: directory))

    try await writer.writeGIF(at: source)
    let file = try clipboardFile(on: pasteboard)
    XCTAssertEqual(file.pathExtension, "gif")
    XCTAssertNotEqual(file, source)
    XCTAssertNil(pasteboard.data(forType: .png))
    XCTAssertNil(pasteboard.data(forType: .tiff))
    XCTAssertEqual(try Data(contentsOf: file), bytes)
    let image = try XCTUnwrap(CGImageSourceCreateWithURL(file as CFURL, nil))
    XCTAssertEqual(CGImageSourceGetCount(image), 2)
    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

    try FileManager.default.removeItem(at: source.deletingLastPathComponent())
    _ = GIFClipboardFileStore(directory: directory)
    XCTAssertEqual(try Data(contentsOf: try clipboardFile(on: pasteboard)), bytes)
  }

  func testNextFileCopyReplacesRetainedFileWithoutAccumulatingExports() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appendingPathComponent("first.gif")
    _ = try animatedGIF(at: first)
    let second = root.appendingPathComponent("second.gif")
    let expected = try animatedGIF(at: second, delay: 0.2)
    let directory = root.appendingPathComponent("clipboard")
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let writer = NSPasteboardGIFFileWriter(
      pasteboard: pasteboard, store: GIFClipboardFileStore(directory: directory))
    try await writer.writeGIF(at: first)
    let firstURL = try clipboardFile(on: pasteboard)
    try await writer.writeGIF(at: second)
    XCTAssertEqual(try clipboardFile(on: pasteboard), firstURL)
    XCTAssertEqual(try Data(contentsOf: firstURL), expected)
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: directory.path), ["gifferent.gif"])
  }

  func testMissingOversizedAndCancelledCopiesPreservePreviousFileAndClipboard() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("preview.gif")
    let bytes = try animatedGIF(at: source)
    let directory = root.appendingPathComponent("clipboard")
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let store = GIFClipboardFileStore(directory: directory)
    let writer = NSPasteboardGIFFileWriter(pasteboard: pasteboard, store: store)
    try await writer.writeGIF(at: source)
    let file = try clipboardFile(on: pasteboard)
    let changeCount = pasteboard.changeCount
    do {
      try await writer.writeGIF(at: root.appendingPathComponent("missing.gif"))
      XCTFail("expected a missing source failure")
    } catch {}
    let limited = NSPasteboardGIFFileWriter(
      pasteboard: pasteboard,
      store: GIFClipboardFileStore(directory: directory, maximumFileBytes: 1))
    do {
      try await limited.writeGIF(at: source)
      XCTFail("expected a size limit failure")
    } catch {}
    let task = Task { @MainActor in try await writer.writeGIF(at: source) }
    task.cancel()
    do {
      try await task.value
      XCTFail("expected cancellation")
    } catch is CancellationError {} catch { XCTFail("unexpected error: \(error)") }
    XCTAssertEqual(pasteboard.changeCount, changeCount)
    XCTAssertEqual(try clipboardFile(on: pasteboard), file)
    XCTAssertEqual(try Data(contentsOf: file), bytes)
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: directory.path), ["gifferent.gif"])
  }

  func testImageCopyStillPublishesGIFBytesWithoutAFileAttachment() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("preview.gif")
    let bytes = try animatedGIF(at: source)
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    try await NSPasteboardGIFWriter(pasteboard: pasteboard).writeGIF(at: source)
    XCTAssertEqual(pasteboard.data(forType: .init("com.compuserve.gif")), bytes)
    XCTAssertNil(pasteboard.string(forType: .fileURL))
  }

  private func clipboardFile(on pasteboard: NSPasteboard) throws -> URL {
    let files =
      pasteboard.readObjects(
        forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
    return try XCTUnwrap(files?.first)
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("gifferent-clipboard-\(UUID())")
  }

  private func animatedGIF(at url: URL, delay: Double = 0.1) throws -> Data {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 2, nil))
    CGImageDestinationSetProperties(
      destination,
      [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for pixel: [UInt8] in [[255, 0, 0, 255], [0, 255, 0, 255]] {
      let provider = try XCTUnwrap(CGDataProvider(data: Data(pixel) as CFData))
      let image = try XCTUnwrap(
        CGImage(
          width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
          provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
      CGImageDestinationAddImage(
        destination, image,
        [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
    }
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return try Data(contentsOf: url)
  }
}
