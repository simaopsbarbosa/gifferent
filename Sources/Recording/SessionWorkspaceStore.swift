import Darwin
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
  case unsafeWorkspace
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
  private struct DirectoryIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
  }

  private struct Session {
    let directory: URL
    let directoryIdentity: DirectoryIdentity
    var frameCount = 0
    var temporaryBytes: Int64 = 0
    var firstTimestamp: TimeInterval?
    var lastTimestamp: TimeInterval?
    var stopReason: RecordingStopReason?
    var previewReady = false
    var previewReserved = false

    var isRecording: Bool { stopReason == nil }
  }

  private let rootDirectory: URL
  private let maximumSessionBytes: Int64
  private let minimumFreeBytes: Int64
  private let fileManager: FileManager
  private var sessions: [RecordingSessionID: Session] = [:]
  private var rootIdentity: DirectoryIdentity?

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
    try verifyRootDirectory()
    let id = RecordingSessionID()
    let directory = directoryURL(for: id)
    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )
    let identity = try identityOfDirectory(at: directory)
    sessions[id] = Session(directory: directory, directoryIdentity: identity)
    return id
  }

  func appendFrame(_ data: Data, timestamp: TimeInterval, to id: RecordingSessionID) throws -> URL {
    guard var session = sessions[id] else { throw SessionWorkspaceError.unknownSession }
    guard session.isRecording else { throw SessionWorkspaceError.invalidState }
    try verify(session)
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
    guard var session = sessions[id] else { throw SessionWorkspaceError.unknownSession }
    guard !session.isRecording, !session.previewReady, !session.previewReserved else {
      throw SessionWorkspaceError.invalidState
    }
    try verify(session)
    let remaining = maximumSessionBytes - session.temporaryBytes
    try checkCapacity(adding: 1, current: session.temporaryBytes)
    let previewURL = session.directory.appendingPathComponent("preview.gif", isDirectory: false)
    guard !entryExists(at: previewURL) else { throw SessionWorkspaceError.invalidPreviewFile }
    session.previewReserved = true
    sessions[id] = session
    return PreviewOutputReservation(
      url: previewURL,
      maximumBytes: remaining
    )
  }

  @discardableResult
  func commitPreviewOutput(for id: RecordingSessionID) throws -> RecordingSessionSnapshot {
    guard var session = sessions[id] else { throw SessionWorkspaceError.unknownSession }
    guard !session.isRecording, !session.previewReady, session.previewReserved else {
      throw SessionWorkspaceError.invalidState
    }
    try verify(session)
    let previewURL = session.directory.appendingPathComponent("preview.gif", isDirectory: false)
    do {
      let fileSize = try sizeOfRegularFile(at: previewURL)
      let bytes = Int64(fileSize)
      guard bytes <= maximumSessionBytes - session.temporaryBytes else {
        throw SessionWorkspaceError.sizeLimitExceeded
      }
      session.temporaryBytes += bytes
      session.previewReady = true
      session.previewReserved = false
      sessions[id] = session
      return snapshot(of: session)
    } catch {
      try? fileManager.removeItem(at: previewURL)
      session.previewReserved = false
      sessions[id] = session
      throw error
    }
  }

  func abandonPreviewOutput(for id: RecordingSessionID) throws {
    guard var session = sessions[id] else { throw SessionWorkspaceError.unknownSession }
    guard session.previewReserved else { throw SessionWorkspaceError.invalidState }
    try verify(session)
    let previewURL = session.directory.appendingPathComponent("preview.gif", isDirectory: false)
    if entryExists(at: previewURL) {
      try fileManager.removeItem(at: previewURL)
    }
    session.previewReserved = false
    sessions[id] = session
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
    try verifyRootDirectory()
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
    try verify(session)
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

  private func verifyRootDirectory() throws {
    var info = stat()
    guard lstat(rootDirectory.path, &info) == 0,
      info.st_mode & S_IFMT == S_IFDIR,
      info.st_uid == geteuid()
    else { throw SessionWorkspaceError.unsafeWorkspace }
    if info.st_mode & 0o077 != 0 {
      try fileManager.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: rootDirectory.path
      )
    }
    let identity = try identityOfDirectory(at: rootDirectory)
    if let rootIdentity, rootIdentity != identity {
      throw SessionWorkspaceError.unsafeWorkspace
    }
    rootIdentity = identity
  }

  private func verify(_ session: Session) throws {
    try verifyRootDirectory()
    guard try identityOfDirectory(at: session.directory) == session.directoryIdentity else {
      throw SessionWorkspaceError.unsafeWorkspace
    }
  }

  private func identityOfDirectory(at url: URL) throws -> DirectoryIdentity {
    var info = stat()
    guard lstat(url.path, &info) == 0,
      info.st_mode & S_IFMT == S_IFDIR,
      info.st_uid == geteuid(),
      info.st_mode & 0o077 == 0
    else { throw SessionWorkspaceError.unsafeWorkspace }
    return DirectoryIdentity(device: info.st_dev, inode: info.st_ino)
  }

  private func sizeOfRegularFile(at url: URL) throws -> off_t {
    var info = stat()
    guard lstat(url.path, &info) == 0,
      info.st_mode & S_IFMT == S_IFREG,
      info.st_size > 0
    else { throw SessionWorkspaceError.invalidPreviewFile }
    return info.st_size
  }

  private func entryExists(at url: URL) -> Bool {
    var info = stat()
    return lstat(url.path, &info) == 0
  }
}
