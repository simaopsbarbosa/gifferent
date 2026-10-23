import Foundation
import XCTest

@testable import gifferent

final class SessionWorkspaceStoreTests: XCTestCase {
  func testPartialRecordingRetainsPreviewUntilCloseAfterExport() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let root = base.appendingPathComponent("sessions", isDirectory: true)
    let exported = base.appendingPathComponent("saved.gif")
    let store = SessionWorkspaceStore(
      rootDirectory: root,
      maximumSessionBytes: 1_024,
      minimumFreeBytes: 0
    )

    let id = try await store.start()
    let frame = try await store.appendFrame(Data([1, 2, 3]), timestamp: 1, to: id)
    let stopped = try await store.stop(id, reason: .windowUnavailable)
    XCTAssertEqual(stopped.frameCount, 1)
    XCTAssertEqual(stopped.firstTimestamp, 1)
    XCTAssertTrue(stopped.isPartialResult)
    XCTAssertTrue(FileManager.default.fileExists(atPath: frame.path))

    let reservation = try await store.reservePreviewOutput(for: id)
    XCTAssertEqual(reservation.maximumBytes, 1_021)
    try Data([71, 73, 70]).write(to: reservation.url)
    let committed = try await store.commitPreviewOutput(for: id)
    XCTAssertTrue(committed.previewReady)
    XCTAssertEqual(committed.temporaryBytes, 6)
    XCTAssertTrue(FileManager.default.fileExists(atPath: reservation.url.path))

    try FileManager.default.copyItem(at: reservation.url, to: exported)
    try await store.closePreviewAfterExport(id)
    XCTAssertFalse(FileManager.default.fileExists(atPath: frame.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: reservation.url.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: exported.path))
  }

  func testNoUsableFramesRemovesSession() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let root = base.appendingPathComponent("sessions", isDirectory: true)
    let store = SessionWorkspaceStore(
      rootDirectory: root,
      maximumSessionBytes: 1_024,
      minimumFreeBytes: 0
    )

    let id = try await store.start()
    do {
      _ = try await store.stop(id, reason: .displayUnavailable)
      XCTFail("expected empty capture to fail")
    } catch let error as SessionWorkspaceError {
      XCTAssertEqual(error, .noUsableFrames)
    }
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
  }

  func testCancelAndDiscardRemoveUnfinishedMedia() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let root = base.appendingPathComponent("sessions", isDirectory: true)
    let store = SessionWorkspaceStore(
      rootDirectory: root, maximumSessionBytes: 1_024, minimumFreeBytes: 0
    )

    let recording = try await store.start()
    let frame = try await store.appendFrame(Data([1]), timestamp: 0, to: recording)
    try await store.cancel(recording)
    XCTAssertFalse(FileManager.default.fileExists(atPath: frame.path))
    await assertThrowsSessionError(.unknownSession) {
      _ = try await store.snapshot(for: recording)
    }

    let preview = try await store.start()
    _ = try await store.appendFrame(Data([2]), timestamp: 0, to: preview)
    _ = try await store.stop(preview, reason: .user)
    let reservation = try await store.reservePreviewOutput(for: preview)
    try Data([71, 73, 70]).write(to: reservation.url)
    try await store.discard(preview)
    XCTAssertFalse(FileManager.default.fileExists(atPath: reservation.url.path))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
  }

  func testQuotaAndTimestampRejectWritesWithoutChangingFrames() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let store = SessionWorkspaceStore(
      rootDirectory: base.appendingPathComponent("sessions"),
      maximumSessionBytes: 4,
      minimumFreeBytes: 0
    )
    let id = try await store.start()
    _ = try await store.appendFrame(Data([1, 2]), timestamp: 2, to: id)

    await assertThrowsSessionError(.invalidTimestamp) {
      _ = try await store.appendFrame(Data([3]), timestamp: 1, to: id)
    }
    await assertThrowsSessionError(.emptyFrame) {
      _ = try await store.appendFrame(Data(), timestamp: 3, to: id)
    }
    await assertThrowsSessionError(.sizeLimitExceeded) {
      _ = try await store.appendFrame(Data([3, 4, 5]), timestamp: 3, to: id)
    }
    let snapshot = try await store.snapshot(for: id)
    XCTAssertEqual(snapshot.frameCount, 1)
    XCTAssertEqual(snapshot.temporaryBytes, 2)
  }

  func testDiscardAndNextLaunchCleanupDoNotTouchOtherFiles() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let root = base.appendingPathComponent("sessions", isDirectory: true)
    let outside = base.appendingPathComponent("saved.gif")
    let unrelated = root.appendingPathComponent("gifferent-session-not-a-uuid")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
    try Data([71, 73, 70]).write(to: outside)
    let firstLaunch = SessionWorkspaceStore(
      rootDirectory: root,
      maximumSessionBytes: 1_024,
      minimumFreeBytes: 0
    )
    let abandoned = try await firstLaunch.start()
    let frame = try await firstLaunch.appendFrame(Data([1]), timestamp: 0, to: abandoned)

    let secondLaunch = SessionWorkspaceStore(
      rootDirectory: root,
      maximumSessionBytes: 1_024,
      minimumFreeBytes: 0
    )
    try await secondLaunch.cleanupOrphans()
    XCTAssertFalse(FileManager.default.fileExists(atPath: frame.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))

    let newSession = try await secondLaunch.start()
    _ = try await secondLaunch.appendFrame(Data([2]), timestamp: 0, to: newSession)
    try await secondLaunch.discard(newSession)
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: root.path),
      ["gifferent-session-not-a-uuid"]
    )
  }

  func testDiskReserveRejectsWrite() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let store = SessionWorkspaceStore(
      rootDirectory: base.appendingPathComponent("sessions"),
      maximumSessionBytes: 1_024,
      minimumFreeBytes: Int64.max / 2
    )
    let id = try await store.start()
    await assertThrowsSessionError(.insufficientDiskSpace) {
      _ = try await store.appendFrame(Data([1]), timestamp: 0, to: id)
    }
  }

  func testSymlinkRootAndReplacedSessionDirectoryRejectWrites() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let outside = base.appendingPathComponent("outside", isDirectory: true)
    let rootLink = base.appendingPathComponent("linked-sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: rootLink, withDestinationURL: outside)

    let linkedStore = SessionWorkspaceStore(
      rootDirectory: rootLink, maximumSessionBytes: 1_024, minimumFreeBytes: 0
    )
    await assertThrowsSessionError(.unsafeWorkspace) {
      _ = try await linkedStore.start()
    }
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])

    let root = base.appendingPathComponent("sessions", isDirectory: true)
    let store = SessionWorkspaceStore(
      rootDirectory: root, maximumSessionBytes: 1_024, minimumFreeBytes: 0
    )
    let id = try await store.start()
    let sessionDirectory = root.appendingPathComponent(
      "gifferent-session-\(id.rawValue.uuidString)")
    let moved = base.appendingPathComponent("moved", isDirectory: true)
    try FileManager.default.moveItem(at: sessionDirectory, to: moved)
    try FileManager.default.createSymbolicLink(at: sessionDirectory, withDestinationURL: outside)
    await assertThrowsSessionError(.unsafeWorkspace) {
      _ = try await store.appendFrame(Data([1]), timestamp: 0, to: id)
    }
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
  }

  func testPreviewSymlinkCannotBeCommittedAndReservationCanRetry() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    let outside = base.appendingPathComponent("saved.gif")
    try Data([71, 73, 70]).write(to: outside)
    let store = SessionWorkspaceStore(
      rootDirectory: base.appendingPathComponent("sessions"),
      maximumSessionBytes: 8,
      minimumFreeBytes: 0
    )
    let id = try await store.start()
    _ = try await store.appendFrame(Data([1]), timestamp: 0, to: id)
    _ = try await store.stop(id, reason: .user)
    let preexisting = base.appendingPathComponent("sessions")
      .appendingPathComponent("gifferent-session-\(id.rawValue.uuidString)")
      .appendingPathComponent("preview.gif")
    try FileManager.default.createSymbolicLink(at: preexisting, withDestinationURL: outside)
    await assertThrowsSessionError(.invalidPreviewFile) {
      _ = try await store.reservePreviewOutput(for: id)
    }
    try FileManager.default.removeItem(at: preexisting)
    let reservation = try await store.reservePreviewOutput(for: id)
    try FileManager.default.createSymbolicLink(at: reservation.url, withDestinationURL: outside)

    await assertThrowsSessionError(.invalidPreviewFile) {
      _ = try await store.commitPreviewOutput(for: id)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: reservation.url.path))
    XCTAssertEqual(try Data(contentsOf: outside), Data([71, 73, 70]))
    let retry = try await store.reservePreviewOutput(for: id)
    try Data([71, 73, 70]).write(to: retry.url)
    let committed = try await store.commitPreviewOutput(for: id)
    XCTAssertTrue(committed.previewReady)
  }

  func testDuplicateReservationAbandonAndOversizeCleanup() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let store = SessionWorkspaceStore(
      rootDirectory: base.appendingPathComponent("sessions"),
      maximumSessionBytes: 4,
      minimumFreeBytes: 0
    )
    let id = try await store.start()
    _ = try await store.appendFrame(Data([1]), timestamp: 0, to: id)
    _ = try await store.stop(id, reason: .user)
    let reservation = try await store.reservePreviewOutput(for: id)
    await assertThrowsSessionError(.invalidState) {
      _ = try await store.reservePreviewOutput(for: id)
    }
    try Data([1, 2]).write(to: reservation.url)
    try await store.abandonPreviewOutput(for: id)
    XCTAssertFalse(FileManager.default.fileExists(atPath: reservation.url.path))

    let retry = try await store.reservePreviewOutput(for: id)
    let missing = base.appendingPathComponent("missing.gif")
    try FileManager.default.createSymbolicLink(at: retry.url, withDestinationURL: missing)
    try await store.abandonPreviewOutput(for: id)
    XCTAssertThrowsError(try FileManager.default.destinationOfSymbolicLink(atPath: retry.url.path))

    let oversize = try await store.reservePreviewOutput(for: id)
    try Data([1, 2, 3, 4]).write(to: oversize.url)
    await assertThrowsSessionError(.sizeLimitExceeded) {
      _ = try await store.commitPreviewOutput(for: id)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: oversize.url.path))
    let snapshot = try await store.snapshot(for: id)
    XCTAssertEqual(snapshot.temporaryBytes, 1)
    _ = try await store.reservePreviewOutput(for: id)
  }

  func testCleanupKeepsActiveConcurrentSessionsAndUnlinksOrphanSymlink() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let root = base.appendingPathComponent("sessions", isDirectory: true)
    let outside = base.appendingPathComponent("outside", isDirectory: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    let store = SessionWorkspaceStore(
      rootDirectory: root, maximumSessionBytes: 1_024, minimumFreeBytes: 0
    )
    let first = try await store.start()
    let second = try await store.start()
    let firstFrame = try await store.appendFrame(Data([1]), timestamp: 0, to: first)
    let secondFrame = try await store.appendFrame(Data([2]), timestamp: 0, to: second)
    let orphan = root.appendingPathComponent("gifferent-session-\(UUID().uuidString)")
    try FileManager.default.createSymbolicLink(at: orphan, withDestinationURL: outside)

    try await store.cleanupOrphans()
    XCTAssertTrue(FileManager.default.fileExists(atPath: firstFrame.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: secondFrame.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
  }

  private func uniqueTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
  }
}

private func assertThrowsSessionError(
  _ expected: SessionWorkspaceError,
  file: StaticString = #filePath,
  line: UInt = #line,
  _ operation: () async throws -> Void
) async {
  do {
    try await operation()
    XCTFail("expected \(expected)", file: file, line: line)
  } catch let error as SessionWorkspaceError {
    XCTAssertEqual(error, expected, file: file, line: line)
  } catch {
    XCTFail("unexpected error: \(error)", file: file, line: line)
  }
}
