import Foundation

struct RecordingSessionID: Hashable, Sendable {
  let rawValue: UUID

  init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

enum RecordingStopReason: Sendable, Equatable {
  case user
  case windowUnavailable
  case displayUnavailable
}

enum SessionWorkspaceError: Error, Equatable {
  case unknownSession
  case invalidState
  case noUsableFrames
  case emptyFrame
  case invalidTimestamp
  case sizeLimitExceeded
  case insufficientDiskSpace
  case unavailableDiskSpace
  case invalidPreviewFile
}

struct RecordingSessionSnapshot: Sendable, Equatable {
  let frameCount: Int
  let temporaryBytes: Int64
  let firstTimestamp: TimeInterval?
  let lastTimestamp: TimeInterval?
  let stopReason: RecordingStopReason?
  let previewReady: Bool

  var isPartialResult: Bool {
    stopReason == .windowUnavailable || stopReason == .displayUnavailable
  }
}

struct PreviewOutputReservation: Sendable {
  let url: URL
  let maximumBytes: Int64
}

actor SessionWorkspaceStore {
  private struct Session {
    let directory: URL
    var frameCount = 0
    var temporaryBytes: Int64 = 0
    var firstTimestamp: TimeInterval?
    var lastTimestamp: TimeInterval?
    var stopReason: RecordingStopReason?
    var previewReady = false

    var isRecording: Bool { stopReason == nil }
  }

  private let rootDirectory: URL
  private let maximumSessionBytes: Int64
  private let minimumFreeBytes: Int64
  private let fileManager: FileManager
  private var sessions: [RecordingSessionID: Session] = [:]

  init(
    rootDirectory: URL,
    maximumSessionBytes: Int64,
    minimumFreeBytes: Int64 = 64 * 1_024 * 1_024,
    fileManager: FileManager = .default
  ) {
    precondition(maximumSessionBytes > 0)
    precondition(minimumFreeBytes >= 0)
    self.rootDirectory = rootDirectory.standardizedFileURL
    self.maximumSessionBytes = maximumSessionBytes
    self.minimumFreeBytes = minimumFreeBytes
    self.fileManager = fileManager
  }

  func start() throws -> RecordingSessionID {
    try fileManager.createDirectory(
      at: rootDirectory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let id = RecordingSessionID()
    let directory = directoryURL(for: id)
    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )
    sessions[id] = Session(directory: directory)
    return id
  }

  func appendFrame(_ data: Data, timestamp: TimeInterval, to id: RecordingSessionID) throws -> URL {
    guard var session = sessions[id] else { throw SessionWorkspaceError.unknownSession }
    guard session.isRecording else { throw SessionWorkspaceError.invalidState }
    guard timestamp.isFinite, timestamp >= 0,
      timestamp >= (session.lastTimestamp ?? 0)
    else { throw SessionWorkspaceError.invalidTimestamp }
    guard !data.isEmpty else { throw SessionWorkspaceError.emptyFrame }
    let bytes = Int64(data.count)
    try checkCapacity(adding: bytes, current: session.temporaryBytes)
    let frameNumber = session.frameCount + 1
    let destination = session.directory.appendingPathComponent(
      String(format: "frame-%08d.bin", frameNumber),
      isDirectory: false
    )
    try data.write(to: destination, options: .atomic)
    session.frameCount = frameNumber
    session.temporaryBytes += bytes
    session.firstTimestamp = session.firstTimestamp ?? timestamp
    session.lastTimestamp = timestamp
    sessions[id] = session
    return destination
  }

  @discardableResult
  func stop(_ id: RecordingSessionID, reason: RecordingStopReason) throws
    -> RecordingSessionSnapshot
  {
    guard var session = sessions[id] else { throw SessionWorkspaceError.unknownSession }
    guard session.isRecording else { throw SessionWorkspaceError.invalidState }
    guard session.frameCount > 0 else {
      try remove(id)
      throw SessionWorkspaceError.noUsableFrames
    }
    session.stopReason = reason
    sessions[id] = session
    return snapshot(of: session)
  }

  func reservePreviewOutput(for id: RecordingSessionID) throws -> PreviewOutputReservation {
    guard let session = sessions[id] else { throw SessionWorkspaceError.unknownSession }
    guard !session.isRecording, !session.previewReady else {
      throw SessionWorkspaceError.invalidState
    }
    let remaining = maximumSessionBytes - session.temporaryBytes
    try checkCapacity(adding: 1, current: session.temporaryBytes)
    return PreviewOutputReservation(
      url: session.directory.appendingPathComponent("preview.gif", isDirectory: false),
      maximumBytes: remaining
    )
  }

  @discardableResult
  func commitPreviewOutput(for id: RecordingSessionID) throws -> RecordingSessionSnapshot {
    guard var session = sessions[id] else { throw SessionWorkspaceError.unknownSession }
    guard !session.isRecording, !session.previewReady else {
      throw SessionWorkspaceError.invalidState
    }
    let previewURL = session.directory.appendingPathComponent("preview.gif", isDirectory: false)
    let values = try previewURL.resourceValues(forKeys: [
      .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
    ])
    guard values.isRegularFile == true, values.isSymbolicLink != true,
      let fileSize = values.fileSize, fileSize > 0
    else { throw SessionWorkspaceError.invalidPreviewFile }
    let bytes = Int64(fileSize)
    guard bytes <= maximumSessionBytes - session.temporaryBytes else {
      try? fileManager.removeItem(at: previewURL)
      throw SessionWorkspaceError.sizeLimitExceeded
    }
    session.temporaryBytes += bytes
    session.previewReady = true
    sessions[id] = session
    return snapshot(of: session)
  }

  func snapshot(for id: RecordingSessionID) throws -> RecordingSessionSnapshot {
    guard let session = sessions[id] else { throw SessionWorkspaceError.unknownSession }
    return snapshot(of: session)
  }

  func cancel(_ id: RecordingSessionID) throws {
    try remove(id)
  }

  func discard(_ id: RecordingSessionID) throws {
    try remove(id)
  }

  func closePreviewAfterExport(_ id: RecordingSessionID) throws {
    guard let session = sessions[id] else { throw SessionWorkspaceError.unknownSession }
    guard session.previewReady else { throw SessionWorkspaceError.invalidState }
    try remove(id)
  }

  func cleanupOrphans() throws {
    guard fileManager.fileExists(atPath: rootDirectory.path) else { return }
    let children = try fileManager.contentsOfDirectory(
      at: rootDirectory,
      includingPropertiesForKeys: nil
    )
    let activeNames = Set(sessions.values.map { $0.directory.lastPathComponent })
    for child in children where isSessionDirectoryName(child.lastPathComponent) {
      guard !activeNames.contains(child.lastPathComponent) else { continue }
      try fileManager.removeItem(at: child)
    }
  }

  private func remove(_ id: RecordingSessionID) throws {
    guard let session = sessions[id] else { throw SessionWorkspaceError.unknownSession }
    try fileManager.removeItem(at: session.directory)
    sessions.removeValue(forKey: id)
  }

  private func directoryURL(for id: RecordingSessionID) -> URL {
    rootDirectory.appendingPathComponent(
      "gifferent-session-\(id.rawValue.uuidString)", isDirectory: true
    )
  }

  private func isSessionDirectoryName(_ name: String) -> Bool {
    let prefix = "gifferent-session-"
    guard name.hasPrefix(prefix) else { return false }
    return UUID(uuidString: String(name.dropFirst(prefix.count))) != nil
  }

  private func snapshot(of session: Session) -> RecordingSessionSnapshot {
    RecordingSessionSnapshot(
      frameCount: session.frameCount,
      temporaryBytes: session.temporaryBytes,
      firstTimestamp: session.firstTimestamp,
      lastTimestamp: session.lastTimestamp,
      stopReason: session.stopReason,
      previewReady: session.previewReady
    )
  }

  private func checkCapacity(adding bytes: Int64, current: Int64) throws {
    guard bytes <= maximumSessionBytes - current else {
      throw SessionWorkspaceError.sizeLimitExceeded
    }
    let values = try rootDirectory.resourceValues(forKeys: [
      .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
    ])
    let fileSystemFree =
      try? fileManager.attributesOfFileSystem(forPath: rootDirectory.path)[
        .systemFreeSize
      ] as? NSNumber
    let available = [
      values.volumeAvailableCapacityForImportantUsage,
      values.volumeAvailableCapacity.map(Int64.init),
      fileSystemFree?.int64Value,
    ].compactMap { $0 }.filter { $0 > 0 }.min()
    guard let available else {
      throw SessionWorkspaceError.unavailableDiskSpace
    }
    guard available >= minimumFreeBytes,
      available - minimumFreeBytes >= bytes
    else {
      throw SessionWorkspaceError.insufficientDiskSpace
    }
  }
}
