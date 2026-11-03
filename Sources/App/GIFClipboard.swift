import AppKit
import Foundation

@MainActor
struct NSPasteboardGIFWriter: GIFClipboardWriting {
  var pasteboard: NSPasteboard = .general
  func writeGIF(at url: URL) async throws {
    let data = try await Task.detached(priority: .userInitiated) {
      try Data(contentsOf: url, options: .mappedIfSafe)
    }.value
    pasteboard.clearContents()
    guard pasteboard.setData(data, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))
    else { throw NSError(domain: "gifferent.clipboard", code: 1) }
  }
}

/// retains one file outside the recording workspace so closing a preview cannot break paste.
/// file copying runs on this actor, with at most 512 mib retained plus 512 mib while staging.
actor GIFClipboardFileStore {
  static let shared = GIFClipboardFileStore()
  private let directory: URL
  private let maximumFileBytes: Int64

  init(directory: URL? = nil, maximumFileBytes: Int64 = 512 * 1_024 * 1_024) {
    self.directory =
      directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
      .first.map { $0.appendingPathComponent("gifferent/clipboard-file", isDirectory: true) }
      ?? FileManager.default.temporaryDirectory.appendingPathComponent(
        "gifferent/clipboard-file", isDirectory: true)
    self.maximumFileBytes = maximumFileBytes
  }

  func copyForClipboard(_ source: URL) throws -> URL {
    try Task.checkCancellation()
    let manager = FileManager.default
    let attributes = try manager.attributesOfItem(atPath: source.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular,
      let bytes = attributes[.size] as? NSNumber,
      bytes.int64Value > 0, bytes.int64Value <= maximumFileBytes
    else { throw CocoaError(.fileReadTooLarge) }
    try manager.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let destination = directory.appendingPathComponent("gifferent.gif")
    let pending = directory.appendingPathComponent(".pending.gif")
    if manager.fileExists(atPath: pending.path) { try manager.removeItem(at: pending) }
    defer { try? manager.removeItem(at: pending) }
    try manager.copyItem(at: source, to: pending)
    try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pending.path)
    try Task.checkCancellation()
    if manager.fileExists(atPath: destination.path) {
      _ = try manager.replaceItemAt(destination, withItemAt: pending)
    } else {
      try manager.moveItem(at: pending, to: destination)
    }
    return destination
  }
}

@MainActor
struct NSPasteboardGIFFileWriter: GIFClipboardWriting {
  var pasteboard: NSPasteboard = .general
  var store: GIFClipboardFileStore = .shared

  func writeGIF(at url: URL) async throws {
    let file = try await store.copyForClipboard(url)
    try Task.checkCancellation()
    pasteboard.clearContents()
    guard pasteboard.writeObjects([file as NSURL]) else {
      throw NSError(domain: "gifferent.clipboard", code: 1)
    }
  }
}
