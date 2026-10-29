import Darwin
import Foundation
import ImageIO

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
  case outputCleanupFailed
  case missingFrame
  case corruptFrame
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

struct CompressedPreviewOutputReservation: Sendable, Equatable {
  let url: URL
  /// the output adapter must enforce this limit while writing; commit validates it again.
  let maximumBytes: Int64
  let sourceURL: URL?
  let cacheDirectory: URL?
  /// temporary encoder frames or pixel caches must stay within this reserved workspace.
  let maximumCacheBytes: Int64
  let token: UUID

  init(
    url: URL,
    maximumBytes: Int64,
    sourceURL: URL? = nil,
    cacheDirectory: URL? = nil,
    maximumCacheBytes: Int64 = 0,
    token: UUID = UUID()
  ) {
    self.url = url
    self.maximumBytes = maximumBytes
    self.sourceURL = sourceURL?.standardizedFileURL
    self.cacheDirectory = cacheDirectory?.standardizedFileURL
    self.maximumCacheBytes = maximumCacheBytes
    self.token = token
  }
}

struct CapturedPNGFrame: Sendable, Equatable {
  let url: URL
  let timestamp: TimeInterval
}

struct CapturedPNGSequence: Sendable, Equatable {
  let frames: [CapturedPNGFrame]
  let finalFrameDuration: TimeInterval?

  init(frames: [CapturedPNGFrame], finalFrameDuration: TimeInterval? = nil) {
    self.frames = frames
    self.finalFrameDuration = finalFrameDuration
  }
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
    var frameURLs: [URL] = []
    var frameTimestamps: [TimeInterval] = []
    var temporaryBytes: Int64 = 0
    var firstTimestamp: TimeInterval?
    var lastTimestamp: TimeInterval?
    var stopReason: RecordingStopReason?
    var previewReady = false
    var previewURL: URL?
    var previewBytes: Int64?
    var previewReservedURL: URL?
    var previewReservedMaximumBytes: Int64?
    var editedPreviewURLs: [URL: Int64] = [:]
    var compressedPreviewReservation: CompressedPreviewOutputReservation?
    var compressionCacheIdentity: DirectoryIdentity?
    var compressedPreviewURLs: [URL: Int64] = [:]

    var isRecording: Bool { stopReason == nil }
  }

  private let rootDirectory: URL
  private let maximumSessionBytes: Int64
  private let minimumFreeBytes: Int64
  private let fileManager: FileManager
  private let availableDiskBytesProvider: (@Sendable () -> Int64?)?
  private var sessions: [RecordingSessionID: Session] = [:]
  private var rootIdentity: DirectoryIdentity?

  init(
    rootDirectory: URL,
    maximumSessionBytes: Int64,
    minimumFreeBytes: Int64 = 64 * 1_024 * 1_024,
    fileManager: FileManager = .default,
    availableDiskBytesProvider: (@Sendable () -> Int64?)? = nil
  ) {
    precondition(maximumSessionBytes > 0)
    precondition(minimumFreeBytes >= 0)
    self.rootDirectory = rootDirectory.standardizedFileURL
    self.maximumSessionBytes = maximumSessionBytes
    self.minimumFreeBytes = minimumFreeBytes
    self.fileManager = fileManager
    self.availableDiskBytesProvider = availableDiskBytesProvider
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
    try checkCapacity(
      adding: bytes,
      current: session.temporaryBytes,
      reserved: reservedBytes(in: session)
    )
    let frameNumber = session.frameCount + 1
    let destination = session.directory.appendingPathComponent(
      String(format: "frame-%08d.bin", frameNumber),
      isDirectory: false
    )
    try data.write(to: destination, options: .atomic)
    session.frameCount = frameNumber
    session.frameURLs.append(destination)
    session.frameTimestamps.append(timestamp)
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
    guard !session.isRecording, session.previewReservedURL == nil,
      session.compressedPreviewReservation == nil
    else {
      throw SessionWorkspaceError.invalidState
    }
    try verify(session)
    let remaining = maximumSessionBytes - session.temporaryBytes
    guard remaining > 0 else { throw SessionWorkspaceError.sizeLimitExceeded }
    let availableBytes = try availableReservationBytes()
    let maximumBytes = min(remaining, availableBytes)
    guard maximumBytes > 0 else { throw SessionWorkspaceError.insufficientDiskSpace }
    let fileName = session.previewReady ? "preview-edit-\(UUID().uuidString).gif" : "preview.gif"
    let previewURL = session.directory.appendingPathComponent(fileName, isDirectory: false)
    guard !entryExists(at: previewURL) else { throw SessionWorkspaceError.invalidPreviewFile }
    session.previewReservedURL = previewURL
    session.previewReservedMaximumBytes = maximumBytes
    sessions[id] = session
    return PreviewOutputReservation(
      url: previewURL,
      maximumBytes: maximumBytes
    )
  }

  func pngSequence(for id: RecordingSessionID) throws -> CapturedPNGSequence {
    guard let session = sessions[id] else { throw SessionWorkspaceError.unknownSession }
    guard !session.isRecording, session.previewReservedURL == nil,
      session.compressedPreviewReservation == nil
    else {
      throw SessionWorkspaceError.invalidState
    }
    try verify(session)
    guard session.frameURLs.count == session.frameCount,
      session.frameTimestamps.count == session.frameCount,
      session.frameCount > 0
    else { throw SessionWorkspaceError.missingFrame }

    for url in session.frameURLs {
      var info = stat()
      guard lstat(url.path, &info) == 0,
        info.st_mode & S_IFMT == S_IFREG,
        info.st_size > 0
      else { throw SessionWorkspaceError.missingFrame }
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        CGImageSourceGetType(source) == "public.png" as CFString,
        CGImageSourceGetCount(source) == 1,
        CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
      else { throw SessionWorkspaceError.corruptFrame }
    }

    return CapturedPNGSequence(
      frames: zip(session.frameURLs, session.frameTimestamps).map { url, timestamp in
        CapturedPNGFrame(url: url, timestamp: timestamp)
      }
    )
  }

  @discardableResult
  func commitPreviewOutput(
    for id: RecordingSessionID,
    reservation: PreviewOutputReservation? = nil
  ) throws -> RecordingSessionSnapshot {
    guard var session = sessions[id] else { throw SessionWorkspaceError.unknownSession }
    guard !session.isRecording, let reservedURL = session.previewReservedURL,
      let reservedMaximumBytes = session.previewReservedMaximumBytes,
      reservation?.url == nil || reservation?.url == reservedURL
    else {
      throw SessionWorkspaceError.invalidState
    }
    try verify(session)
    do {
      let fileSize = try sizeOfRegularFile(at: reservedURL)
      let bytes = Int64(fileSize)
      guard bytes <= reservedMaximumBytes,
        bytes <= maximumSessionBytes - session.temporaryBytes
      else {
        throw SessionWorkspaceError.sizeLimitExceeded
      }
      session.temporaryBytes += bytes
      session.previewReady = true
      if reservedURL.lastPathComponent == "preview.gif" {
        session.previewURL = reservedURL
        session.previewBytes = bytes
      }
      session.previewReservedURL = nil
      session.previewReservedMaximumBytes = nil
      if reservedURL.lastPathComponent != "preview.gif" {
        session.editedPreviewURLs[reservedURL] = bytes
      }
      sessions[id] = session
      return snapshot(of: session)
    } catch {
      try removeOutputEntry(at: reservedURL)
      session.previewReservedURL = nil
      session.previewReservedMaximumBytes = nil
      sessions[id] = session
      throw error
    }
  }

  func abandonPreviewOutput(
    for id: RecordingSessionID,
    reservation: PreviewOutputReservation? = nil
  ) throws {
    guard var session = sessions[id] else { throw SessionWorkspaceError.unknownSession }
    guard let reservedURL = session.previewReservedURL,
      session.previewReservedMaximumBytes != nil,
      reservation?.url == nil || reservation?.url == reservedURL
    else { throw SessionWorkspaceError.invalidState }
    try verify(session)
    if entryExists(at: reservedURL) {
      try removeOutputEntry(at: reservedURL)
    }
    session.previewReservedURL = nil
    session.previewReservedMaximumBytes = nil
    sessions[id] = session
  }

  func reserveCompressedPreviewOutput(
    for id: RecordingSessionID
  ) throws -> CompressedPreviewOutputReservation {
    try reserveCompressedPreviewOutput(for: id, sourceURL: nil, maximumCacheBytes: 0)
  }

  func reserveCompressedPreviewOutput(
    for id: RecordingSessionID,
    sourceURL: URL,
    maximumCacheBytes: Int64
  ) throws -> CompressedPreviewOutputReservation {
    try reserveCompressedPreviewOutput(
      for: id, sourceURL: Optional(sourceURL), maximumCacheBytes: maximumCacheBytes
    )
  }

  private func reserveCompressedPreviewOutput(
    for id: RecordingSessionID,
    sourceURL requestedSourceURL: URL?,
    maximumCacheBytes: Int64
  ) throws -> CompressedPreviewOutputReservation {
    guard var session = sessions[id] else { throw SessionWorkspaceError.unknownSession }
    guard !session.isRecording, session.previewReady,
      session.previewReservedURL == nil,
      session.compressedPreviewReservation == nil
    else { throw SessionWorkspaceError.invalidState }
    try verify(session)

    let sourceURL = try accountedSourceURL(requestedSourceURL, in: session)

    let sessionRemaining = maximumSessionBytes - session.temporaryBytes
    guard sessionRemaining > 0 else { throw SessionWorkspaceError.sizeLimitExceeded }
    let availableBytes = try availableReservationBytes()
    let combinedBudget = min(sessionRemaining, availableBytes)
    guard maximumCacheBytes >= 0, maximumCacheBytes < combinedBudget else {
      if combinedBudget <= 0 || availableBytes <= maximumCacheBytes {
        throw SessionWorkspaceError.insufficientDiskSpace
      }
      throw SessionWorkspaceError.sizeLimitExceeded
    }
    let maximumBytes = combinedBudget - maximumCacheBytes
    guard maximumBytes > 0 else { throw SessionWorkspaceError.insufficientDiskSpace }

    let outputURL = session.directory.appendingPathComponent(
      "compressed-\(UUID().uuidString).gif", isDirectory: false
    )
    let cacheDirectory =
      maximumCacheBytes > 0
      ? session.directory.appendingPathComponent(
        "compression-cache-\(UUID().uuidString)", isDirectory: true
      )
      : nil
    guard !entryExists(at: outputURL) else { throw SessionWorkspaceError.invalidPreviewFile }
    let cacheIdentity: DirectoryIdentity?
    if let cacheDirectory {
      guard !entryExists(at: cacheDirectory) else { throw SessionWorkspaceError.unsafeWorkspace }
      try fileManager.createDirectory(
        at: cacheDirectory,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
      cacheIdentity = try identityOfDirectory(at: cacheDirectory)
    } else {
      cacheIdentity = nil
    }
    let reservation = CompressedPreviewOutputReservation(
      url: outputURL,
      maximumBytes: maximumBytes,
      sourceURL: sourceURL,
      cacheDirectory: cacheDirectory,
      maximumCacheBytes: maximumCacheBytes,
      token: UUID()
    )
    session.compressedPreviewReservation = reservation
    session.compressionCacheIdentity = cacheIdentity
    sessions[id] = session
    return reservation
  }

  @discardableResult
  func commitCompressedPreviewOutput(
    for id: RecordingSessionID,
    reservation: CompressedPreviewOutputReservation
  ) throws -> RecordingSessionSnapshot {
    guard var session = sessions[id] else { throw SessionWorkspaceError.unknownSession }
    guard !session.isRecording,
      session.compressedPreviewReservation == reservation,
      !session.compressedPreviewURLs.keys.contains(reservation.url)
    else { throw SessionWorkspaceError.invalidState }
    try verify(session)
    let cacheBytes = try removeCompressionCache(for: reservation, session: session)
    do {
      guard cacheBytes <= reservation.maximumCacheBytes else {
        throw SessionWorkspaceError.sizeLimitExceeded
      }
      let bytes = Int64(try sizeOfRegularFile(at: reservation.url))
      guard bytes <= reservation.maximumBytes,
        bytes <= maximumSessionBytes - session.temporaryBytes
      else { throw SessionWorkspaceError.sizeLimitExceeded }
      session.temporaryBytes += bytes
      session.compressedPreviewURLs[reservation.url] = bytes
      session.compressedPreviewReservation = nil
      session.compressionCacheIdentity = nil
      sessions[id] = session
      return snapshot(of: session)
    } catch {
      do {
        try removeOutputEntry(at: reservation.url)
      } catch {
        throw SessionWorkspaceError.outputCleanupFailed
      }
      session.compressedPreviewReservation = nil
      session.compressionCacheIdentity = nil
      sessions[id] = session
      throw error
    }
  }

  func abandonCompressedPreviewOutput(
    for id: RecordingSessionID,
    reservation: CompressedPreviewOutputReservation
  ) throws {
    guard var session = sessions[id],
      session.compressedPreviewReservation == reservation
    else { throw SessionWorkspaceError.invalidState }
    try verify(session)
    _ = try removeCompressionCache(for: reservation, session: session)
    if entryExists(at: reservation.url) {
      try removeOutputEntry(at: reservation.url)
    }
    session.compressedPreviewReservation = nil
    session.compressionCacheIdentity = nil
    sessions[id] = session
  }

  func keepCompressedPreviewOutput(for id: RecordingSessionID, at url: URL) throws {
    guard var session = sessions[id], session.compressedPreviewURLs[url] != nil else {
      throw SessionWorkspaceError.invalidState
    }
    try verify(session)
    let obsoleteOutputs = session.compressedPreviewURLs.filter { $0.key != url }
    for (obsoleteURL, bytes) in obsoleteOutputs {
      try removeOutputEntry(at: obsoleteURL)
      session.compressedPreviewURLs.removeValue(forKey: obsoleteURL)
      session.temporaryBytes -= bytes
      sessions[id] = session
    }
  }

  func removeCompressedPreviewOutput(for id: RecordingSessionID, at url: URL) throws {
    guard var session = sessions[id], let bytes = session.compressedPreviewURLs[url] else {
      throw SessionWorkspaceError.invalidState
    }
    try verify(session)
    try removeOutputEntry(at: url)
    session.compressedPreviewURLs.removeValue(forKey: url)
    session.temporaryBytes -= bytes
    sessions[id] = session
  }

  func removeEditedPreviewOutput(for id: RecordingSessionID, at url: URL) throws {
    guard var session = sessions[id], let bytes = session.editedPreviewURLs[url] else {
      throw SessionWorkspaceError.invalidState
    }
    try verify(session)
    try fileManager.removeItem(at: url)
    session.editedPreviewURLs.removeValue(forKey: url)
    session.temporaryBytes -= bytes
    sessions[id] = session
  }

  func keepEditedPreviewOutput(for id: RecordingSessionID, at url: URL) throws {
    guard var session = sessions[id], session.editedPreviewURLs[url] != nil else {
      throw SessionWorkspaceError.invalidState
    }
    try verify(session)
    let obsoleteOutputs = session.editedPreviewURLs.filter { $0.key != url }
    for (obsoleteURL, bytes) in obsoleteOutputs {
      try fileManager.removeItem(at: obsoleteURL)
      session.editedPreviewURLs.removeValue(forKey: obsoleteURL)
      session.temporaryBytes -= bytes
      sessions[id] = session
    }
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
    guard session.previewReady, session.previewReservedURL == nil,
      session.compressedPreviewReservation == nil
    else {
      throw SessionWorkspaceError.invalidState
    }
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
    guard session.previewReservedURL == nil,
      session.compressedPreviewReservation == nil
    else {
      throw SessionWorkspaceError.invalidState
    }
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

  private func checkCapacity(adding bytes: Int64, current: Int64, reserved: Int64) throws {
    guard reserved <= maximumSessionBytes - current,
      bytes <= maximumSessionBytes - current - reserved
    else {
      throw SessionWorkspaceError.sizeLimitExceeded
    }
    let availableAfterReservations = try availableReservationBytes()
    guard availableAfterReservations >= bytes else {
      throw SessionWorkspaceError.insufficientDiskSpace
    }
  }

  private func availableReservationBytes() throws -> Int64 {
    let available = try availableDiskBytes()
    guard available >= minimumFreeBytes else {
      throw SessionWorkspaceError.insufficientDiskSpace
    }
    let usableBytes = available - minimumFreeBytes
    var reservedBytes: Int64 = 0
    for session in sessions.values {
      let reservations =
        [session.previewReservedMaximumBytes].compactMap { $0 }
        + [session.compressedPreviewReservation].compactMap { $0 }.flatMap {
          [$0.maximumBytes, $0.maximumCacheBytes]
        }
      for bytes in reservations {
        let (sum, overflow) = reservedBytes.addingReportingOverflow(bytes)
        reservedBytes = overflow ? Int64.max : sum
      }
    }
    guard reservedBytes <= usableBytes else {
      throw SessionWorkspaceError.insufficientDiskSpace
    }
    return usableBytes - reservedBytes
  }

  private func reservedBytes(in session: Session) -> Int64 {
    var total: Int64 = session.previewReservedMaximumBytes ?? 0
    if let reservation = session.compressedPreviewReservation {
      let (sum, overflow) = total.addingReportingOverflow(reservation.maximumBytes)
      total = overflow ? Int64.max : sum
      let (cacheSum, cacheOverflow) = total.addingReportingOverflow(reservation.maximumCacheBytes)
      total = cacheOverflow ? Int64.max : cacheSum
    }
    return total
  }

  private func accountedSourceURL(_ requested: URL?, in session: Session) throws -> URL {
    let source = requested?.standardizedFileURL ?? session.previewURL
    guard let source else { throw SessionWorkspaceError.invalidPreviewFile }
    let trackedBytes =
      if source == session.previewURL {
        session.previewBytes
      } else if let bytes = session.editedPreviewURLs[source] {
        Optional(bytes)
      } else {
        session.compressedPreviewURLs[source]
      }
    guard let trackedBytes, Int64(try sizeOfRegularFile(at: source)) == trackedBytes else {
      throw SessionWorkspaceError.invalidPreviewFile
    }
    return source
  }

  private func removeCompressionCache(
    for reservation: CompressedPreviewOutputReservation,
    session: Session
  ) throws -> Int64 {
    guard let cacheDirectory = reservation.cacheDirectory,
      reservation.maximumCacheBytes > 0,
      let expectedIdentity = session.compressionCacheIdentity,
      cacheDirectory.deletingLastPathComponent().standardizedFileURL
        == session.directory.standardizedFileURL
    else {
      if reservation.maximumCacheBytes == 0, reservation.cacheDirectory == nil { return 0 }
      throw SessionWorkspaceError.outputCleanupFailed
    }
    var info = stat()
    guard lstat(cacheDirectory.path, &info) == 0 else {
      if errno == ENOENT { return 0 }
      throw SessionWorkspaceError.outputCleanupFailed
    }
    guard info.st_mode & S_IFMT == S_IFDIR,
      DirectoryIdentity(device: info.st_dev, inode: info.st_ino) == expectedIdentity
    else { throw SessionWorkspaceError.outputCleanupFailed }
    let measuredBytes = try directoryFileBytes(at: cacheDirectory)
    do {
      try fileManager.removeItem(at: cacheDirectory)
    } catch {
      throw SessionWorkspaceError.outputCleanupFailed
    }
    return measuredBytes
  }

  private func directoryFileBytes(at directory: URL) throws -> Int64 {
    let children: [URL]
    do {
      children = try fileManager.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil
      )
    } catch {
      throw SessionWorkspaceError.outputCleanupFailed
    }
    var total: Int64 = 0
    for child in children {
      var info = stat()
      guard lstat(child.path, &info) == 0 else {
        throw SessionWorkspaceError.outputCleanupFailed
      }
      let bytes: Int64
      switch info.st_mode & S_IFMT {
      case S_IFREG:
        bytes = Int64(info.st_size)
      case S_IFDIR:
        bytes = try directoryFileBytes(at: child)
      case S_IFLNK:
        bytes = Int64(info.st_size)
      default:
        throw SessionWorkspaceError.outputCleanupFailed
      }
      let (sum, overflow) = total.addingReportingOverflow(bytes)
      total = overflow ? Int64.max : sum
    }
    return total
  }

  private func availableDiskBytes() throws -> Int64 {
    if let availableDiskBytesProvider {
      guard let available = availableDiskBytesProvider() else {
        throw SessionWorkspaceError.unavailableDiskSpace
      }
      return available
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
    guard let available else { throw SessionWorkspaceError.unavailableDiskSpace }
    return available
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

  private func removeOutputEntry(at url: URL) throws {
    var info = stat()
    guard lstat(url.path, &info) == 0 else {
      if errno == ENOENT { return }
      throw SessionWorkspaceError.outputCleanupFailed
    }
    guard info.st_mode & S_IFMT == S_IFREG || info.st_mode & S_IFMT == S_IFLNK else {
      throw SessionWorkspaceError.outputCleanupFailed
    }
    do {
      try fileManager.removeItem(at: url)
    } catch {
      throw SessionWorkspaceError.outputCleanupFailed
    }
  }

  private func entryExists(at url: URL) -> Bool {
    var info = stat()
    return lstat(url.path, &info) == 0
  }
}
