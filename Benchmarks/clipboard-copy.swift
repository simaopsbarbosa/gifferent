import AppKit
import Foundation
import ImageIO

// compile alongside Sources/App/GIFClipboard.swift to measure the actual adapters.
@MainActor
protocol GIFClipboardWriting {
  func writeGIF(at url: URL) async throws
}

@main
struct ClipboardCopyBenchmark {
  @MainActor
  static func main() async throws {
    let arguments = CommandLine.arguments
    let mode = arguments[1]
    let source = URL(fileURLWithPath: arguments[2])
    let directory = URL(fileURLWithPath: arguments[3], isDirectory: true)
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let writer: any GIFClipboardWriting =
      mode == "image"
      ? NSPasteboardGIFWriter(pasteboard: pasteboard)
      : NSPasteboardGIFFileWriter(
        pasteboard: pasteboard, store: GIFClipboardFileStore(directory: directory))
    let start = ContinuousClock.now
    try await writer.writeGIF(at: source)
    let elapsed = start.duration(to: .now)
    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    let expected = try Data(contentsOf: source)
    let copied: Data
    if mode == "image" {
      guard let bytes = pasteboard.data(forType: .init("com.compuserve.gif")) else {
        throw CocoaError(.fileReadUnknown)
      }
      copied = bytes
    } else {
      guard let location = pasteboard.string(forType: .fileURL), let file = URL(string: location)
      else {
        throw CocoaError(.fileReadUnknown)
      }
      copied = try Data(contentsOf: file)
    }
    guard copied == expected,
      let decoded = CGImageSourceCreateWithData(copied as CFData, nil)
    else { throw CocoaError(.fileReadCorruptFile) }
    let result: [String: Any] = [
      "mode": mode, "seconds": seconds, "bytes": copied.count,
      "frames": CGImageSourceGetCount(decoded), "byte_identical": true,
    ]
    print(
      String(
        decoding: try JSONSerialization.data(withJSONObject: result, options: .sortedKeys),
        as: UTF8.self))
  }
}
