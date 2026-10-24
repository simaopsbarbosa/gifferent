import Darwin
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

  func testPNGSequenceRequiresStoppedSessionAndPreservesOrderedTimestamps() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let store = SessionWorkspaceStore(
      rootDirectory: base.appendingPathComponent("sessions"),
      maximumSessionBytes: 1_024 * 1_024,
      minimumFreeBytes: 0
    )
    let id = try await store.start()
    let first = try await store.appendFrame(pngFrame(), timestamp: 5.25, to: id)
    let second = try await store.appendFrame(pngFrame(), timestamp: 5.29, to: id)
    await assertThrowsSessionError(.invalidState) {
      _ = try await store.pngSequence(for: id)
    }
    _ = try await store.stop(id, reason: .user)

    let sequence = try await store.pngSequence(for: id)
    XCTAssertEqual(sequence.frames.map(\.url), [first, second])
    XCTAssertEqual(sequence.frames.map(\.timestamp), [5.25, 5.29])
    let reservation = try await store.reservePreviewOutput(for: id)
    await assertThrowsSessionError(.invalidState) {
      _ = try await store.pngSequence(for: id)
    }
    try await store.abandonPreviewOutput(for: id)
    _ = reservation
  }

  func testPNGSequenceRejectsMissingAndCorruptFrameFiles() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let store = SessionWorkspaceStore(
      rootDirectory: base.appendingPathComponent("sessions"),
      maximumSessionBytes: 1_024 * 1_024,
      minimumFreeBytes: 0
    )
    let missingID = try await store.start()
    let missing = try await store.appendFrame(pngFrame(), timestamp: 1, to: missingID)
    _ = try await store.stop(missingID, reason: .user)
    try FileManager.default.removeItem(at: missing)
    await assertThrowsSessionError(.missingFrame) {
      _ = try await store.pngSequence(for: missingID)
    }

    let corruptID = try await store.start()
    let corrupt = try await store.appendFrame(pngFrame(), timestamp: 1, to: corruptID)
    _ = try await store.stop(corruptID, reason: .user)
    try Data("corrupt".utf8).write(to: corrupt)
    await assertThrowsSessionError(.corruptFrame) {
      _ = try await store.pngSequence(for: corruptID)
    }
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
    await assertThrowsSessionError(.invalidState) {
      try await store.discard(preview)
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: reservation.url.path))
    try await store.abandonPreviewOutput(for: preview, reservation: reservation)
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

  func testEditedOutputsRetainOriginalAndPruneOnlyObsoleteTemporaryGIFs() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let store = SessionWorkspaceStore(
      rootDirectory: base.appendingPathComponent("sessions"),
      maximumSessionBytes: 1_024,
      minimumFreeBytes: 0
    )
    let id = try await store.start()
    _ = try await store.appendFrame(pngFrame(), timestamp: 0, to: id)
    _ = try await store.stop(id, reason: .user)

    let originalReservation = try await store.reservePreviewOutput(for: id)
    try Data([71, 73, 70, 56, 57, 97]).write(to: originalReservation.url)
    _ = try await store.commitPreviewOutput(for: id, reservation: originalReservation)
    let originalURL = originalReservation.url

    let firstEdit = try await store.reservePreviewOutput(for: id)
    XCTAssertNotEqual(firstEdit.url, originalURL)
    try Data([1, 2, 3]).write(to: firstEdit.url)
    _ = try await store.commitPreviewOutput(for: id, reservation: firstEdit)
    XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: firstEdit.url.path))

    let secondEdit = try await store.reservePreviewOutput(for: id)
    try Data([4, 5, 6, 7]).write(to: secondEdit.url)
    _ = try await store.commitPreviewOutput(for: id, reservation: secondEdit)
    try await store.keepEditedPreviewOutput(for: id, at: secondEdit.url)

    XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: firstEdit.url.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: secondEdit.url.path))
    let snapshot = try await store.snapshot(for: id)
    XCTAssertEqual(snapshot.temporaryBytes, Int64(try pngFrame().count + 6 + 4))
  }

  func testAbandoningEditReservationPreservesCommittedOriginal() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let store = SessionWorkspaceStore(
      rootDirectory: base.appendingPathComponent("sessions"),
      maximumSessionBytes: 1_024,
      minimumFreeBytes: 0
    )
    let id = try await store.start()
    _ = try await store.appendFrame(pngFrame(), timestamp: 0, to: id)
    _ = try await store.stop(id, reason: .user)
    let original = try await store.reservePreviewOutput(for: id)
    try Data([71, 73, 70]).write(to: original.url)
    _ = try await store.commitPreviewOutput(for: id, reservation: original)
    let edit = try await store.reservePreviewOutput(for: id)
    try Data([1, 2]).write(to: edit.url)
    try await store.abandonPreviewOutput(for: id, reservation: edit)

    XCTAssertTrue(FileManager.default.fileExists(atPath: original.url.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: edit.url.path))
    let snapshot = try await store.snapshot(for: id)
    XCTAssertEqual(snapshot.temporaryBytes, Int64(try pngFrame().count + 3))
  }

  func testDiscardWaitsForPreviewReservationToBeAbandoned() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let store = SessionWorkspaceStore(
      rootDirectory: base.appendingPathComponent("sessions"),
      maximumSessionBytes: 1_024,
      minimumFreeBytes: 0
    )
    let id = try await store.start()
    let frame = try await store.appendFrame(pngFrame(), timestamp: 0, to: id)
    _ = try await store.stop(id, reason: .user)
    let original = try await store.reservePreviewOutput(for: id)
    try Data([71, 73, 70]).write(to: original.url)
    _ = try await store.commitPreviewOutput(for: id, reservation: original)
    let edit = try await store.reservePreviewOutput(for: id)
    try Data([1, 2, 3]).write(to: edit.url)

    await assertThrowsSessionError(.invalidState) {
      try await store.discard(id)
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: frame.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: original.url.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: edit.url.path))
    let snapshot = try await store.snapshot(for: id)
    XCTAssertEqual(snapshot.temporaryBytes, Int64(try pngFrame().count + 3))

    try await store.abandonPreviewOutput(for: id, reservation: edit)
    XCTAssertFalse(FileManager.default.fileExists(atPath: edit.url.path))
    try await store.discard(id)
    XCTAssertFalse(FileManager.default.fileExists(atPath: frame.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: original.url.path))
    await assertThrowsSessionError(.unknownSession) {
      _ = try await store.snapshot(for: id)
    }
  }

  func testCompressedReplacementKeepsBaseAndEditedPreviewOutputs() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let store = SessionWorkspaceStore(
      rootDirectory: base.appendingPathComponent("sessions"),
      maximumSessionBytes: 1_024,
      minimumFreeBytes: 0
    )
    let id = try await store.start()
    _ = try await store.appendFrame(pngFrame(), timestamp: 0, to: id)
    _ = try await store.stop(id, reason: .user)

    let original = try await store.reservePreviewOutput(for: id)
    try Data([71, 73, 70, 56, 57, 97]).write(to: original.url)
    _ = try await store.commitPreviewOutput(for: id, reservation: original)
    let edit = try await store.reservePreviewOutput(for: id)
    try Data([1, 2, 3, 4]).write(to: edit.url)
    _ = try await store.commitPreviewOutput(for: id, reservation: edit)
    try await store.keepEditedPreviewOutput(for: id, at: edit.url)

    let firstCompressed = try await store.reserveCompressedPreviewOutput(for: id)
    XCTAssertGreaterThan(firstCompressed.maximumBytes, 0)
    try Data([10, 11, 12]).write(to: firstCompressed.url)
    _ = try await store.commitCompressedPreviewOutput(for: id, reservation: firstCompressed)

    let replacement = try await store.reserveCompressedPreviewOutput(for: id)
    try Data([20, 21, 22, 23, 24]).write(to: replacement.url)
    _ = try await store.commitCompressedPreviewOutput(for: id, reservation: replacement)
    XCTAssertTrue(FileManager.default.fileExists(atPath: firstCompressed.url.path))
    try await store.keepCompressedPreviewOutput(for: id, at: replacement.url)

    XCTAssertTrue(FileManager.default.fileExists(atPath: original.url.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: edit.url.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: firstCompressed.url.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: replacement.url.path))
    let snapshot = try await store.snapshot(for: id)
    XCTAssertEqual(snapshot.temporaryBytes, Int64(try pngFrame().count + 6 + 4 + 5))
  }

  func testCompressedReservationEnforcesSessionCapacityAndCleansOversizeFile() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let store = SessionWorkspaceStore(
      rootDirectory: base.appendingPathComponent("sessions"),
      maximumSessionBytes: 10,
      minimumFreeBytes: 0
    )
    let id = try await store.start()
    _ = try await store.appendFrame(Data([1]), timestamp: 0, to: id)
    _ = try await store.stop(id, reason: .user)
    let preview = try await store.reservePreviewOutput(for: id)
    try Data([71, 73, 70]).write(to: preview.url)
    _ = try await store.commitPreviewOutput(for: id, reservation: preview)

    let reservation = try await store.reserveCompressedPreviewOutput(for: id)
    XCTAssertEqual(reservation.maximumBytes, 6)
    try Data(repeating: 9, count: 7).write(to: reservation.url)
    await assertThrowsSessionError(.sizeLimitExceeded) {
      _ = try await store.commitCompressedPreviewOutput(for: id, reservation: reservation)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: reservation.url.path))
    let snapshot = try await store.snapshot(for: id)
    XCTAssertEqual(snapshot.temporaryBytes, 4)
  }

  func testAbandonCompressedReservationRemovesOnlyItsFileAndDoesNotChangeAccounting() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let store = SessionWorkspaceStore(
      rootDirectory: base.appendingPathComponent("sessions"),
      maximumSessionBytes: 1_024,
      minimumFreeBytes: 0
    )
    let id = try await store.start()
    _ = try await store.appendFrame(pngFrame(), timestamp: 0, to: id)
    _ = try await store.stop(id, reason: .user)
    let preview = try await store.reservePreviewOutput(for: id)
    try Data([71, 73, 70]).write(to: preview.url)
    _ = try await store.commitPreviewOutput(for: id, reservation: preview)

    let pending = try await store.reserveCompressedPreviewOutput(for: id)
    try Data([1, 2, 3]).write(to: pending.url)
    try await store.abandonCompressedPreviewOutput(for: id, reservation: pending)
    XCTAssertFalse(FileManager.default.fileExists(atPath: pending.url.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: preview.url.path))
    let snapshot = try await store.snapshot(for: id)
    XCTAssertEqual(snapshot.temporaryBytes, Int64(try pngFrame().count + 3))
  }

  func testPreviewAndCompressedReservationsAreSerializedPerSession() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let store = SessionWorkspaceStore(
      rootDirectory: base.appendingPathComponent("sessions"),
      maximumSessionBytes: 1_024,
      minimumFreeBytes: 0
    )
    let id = try await store.start()
    _ = try await store.appendFrame(pngFrame(), timestamp: 0, to: id)
    _ = try await store.stop(id, reason: .user)
    let original = try await store.reservePreviewOutput(for: id)
    try Data([71, 73, 70]).write(to: original.url)
    _ = try await store.commitPreviewOutput(for: id, reservation: original)
    let committedSnapshot = try await store.snapshot(for: id)
    let committedBytes = committedSnapshot.temporaryBytes

    let edit = try await store.reservePreviewOutput(for: id)
    await assertThrowsSessionError(.invalidState) {
      _ = try await store.reserveCompressedPreviewOutput(for: id)
    }
    try Data([1, 2]).write(to: edit.url)
    try await store.abandonPreviewOutput(for: id, reservation: edit)
    XCTAssertFalse(FileManager.default.fileExists(atPath: edit.url.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: original.url.path))
    let afterEditAbandon = try await store.snapshot(for: id)
    XCTAssertEqual(afterEditAbandon.temporaryBytes, committedBytes)

    let compressed = try await store.reserveCompressedPreviewOutput(for: id)
    await assertThrowsSessionError(.invalidState) {
      _ = try await store.reservePreviewOutput(for: id)
    }
    try Data([3, 4]).write(to: compressed.url)
    try await store.abandonCompressedPreviewOutput(for: id, reservation: compressed)
    XCTAssertFalse(FileManager.default.fileExists(atPath: compressed.url.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: original.url.path))
    let afterCompressedAbandon = try await store.snapshot(for: id)
    XCTAssertEqual(afterCompressedAbandon.temporaryBytes, committedBytes)
  }

  func testCompressedOutputRemovalAndExportCleanupPreserveExportedFile() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let root = base.appendingPathComponent("sessions", isDirectory: true)
    let store = SessionWorkspaceStore(
      rootDirectory: root,
      maximumSessionBytes: 1_024,
      minimumFreeBytes: 0
    )
    let id = try await store.start()
    let frame = try await store.appendFrame(pngFrame(), timestamp: 0, to: id)
    _ = try await store.stop(id, reason: .user)
    let preview = try await store.reservePreviewOutput(for: id)
    try Data([71, 73, 70]).write(to: preview.url)
    _ = try await store.commitPreviewOutput(for: id, reservation: preview)
    let compressed = try await store.reserveCompressedPreviewOutput(for: id)
    try Data([1, 2, 3, 4]).write(to: compressed.url)
    _ = try await store.commitCompressedPreviewOutput(for: id, reservation: compressed)

    try await store.removeCompressedPreviewOutput(for: id, at: compressed.url)
    XCTAssertFalse(FileManager.default.fileExists(atPath: compressed.url.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: preview.url.path))
    let retainedCompressed = try await store.reserveCompressedPreviewOutput(for: id)
    try Data([5, 6, 7]).write(to: retainedCompressed.url)
    _ = try await store.commitCompressedPreviewOutput(for: id, reservation: retainedCompressed)
    let exported = base.appendingPathComponent("saved.gif")
    try FileManager.default.copyItem(at: preview.url, to: exported)
    try await store.closePreviewAfterExport(id)
    XCTAssertFalse(FileManager.default.fileExists(atPath: frame.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: preview.url.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: retainedCompressed.url.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: exported.path))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
  }

  func testCompressedReservationBlocksCloseAndDiscardAndRetainsTokenCapUntilAbandoned() async throws
  {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let store = SessionWorkspaceStore(
      rootDirectory: base.appendingPathComponent("sessions"),
      maximumSessionBytes: 1_024,
      minimumFreeBytes: 0
    )
    let id = try await store.start()
    _ = try await store.appendFrame(pngFrame(), timestamp: 0, to: id)
    _ = try await store.stop(id, reason: .user)
    let original = try await store.reservePreviewOutput(for: id)
    try Data([71, 73, 70]).write(to: original.url)
    _ = try await store.commitPreviewOutput(for: id, reservation: original)
    let reservation = try await store.reserveCompressedPreviewOutput(for: id)

    await assertThrowsSessionError(.invalidState) {
      try await store.closePreviewAfterExport(id)
    }
    await assertThrowsSessionError(.invalidState) {
      try await store.discard(id)
    }
    let forgedToken = CompressedPreviewOutputReservation(
      url: reservation.url,
      maximumBytes: reservation.maximumBytes,
      token: UUID()
    )
    await assertThrowsSessionError(.invalidState) {
      _ = try await store.commitCompressedPreviewOutput(for: id, reservation: forgedToken)
    }
    let forgedCap = CompressedPreviewOutputReservation(
      url: reservation.url,
      maximumBytes: reservation.maximumBytes - 1,
      token: reservation.token
    )
    await assertThrowsSessionError(.invalidState) {
      try await store.abandonCompressedPreviewOutput(for: id, reservation: forgedCap)
    }

    try FileManager.default.createDirectory(at: reservation.url, withIntermediateDirectories: false)
    await assertThrowsSessionError(.outputCleanupFailed) {
      try await store.abandonCompressedPreviewOutput(for: id, reservation: reservation)
    }
    await assertThrowsSessionError(.invalidState) {
      _ = try await store.reserveCompressedPreviewOutput(for: id)
    }
    try FileManager.default.removeItem(at: reservation.url)
    try Data([1, 2]).write(to: reservation.url)
    try await store.abandonCompressedPreviewOutput(for: id, reservation: reservation)
    XCTAssertFalse(FileManager.default.fileExists(atPath: reservation.url.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: original.url.path))
    try await store.closePreviewAfterExport(id)
    XCTAssertFalse(FileManager.default.fileExists(atPath: original.url.path))
  }

  func testCompressedReservationCapsAggregateInFlightDiskAcrossSessions() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let store = SessionWorkspaceStore(
      rootDirectory: base.appendingPathComponent("sessions"),
      maximumSessionBytes: 2_048,
      minimumFreeBytes: 10,
      availableDiskBytesProvider: { 100 }
    )
    var sessionIDs: [RecordingSessionID] = []
    for timestamp in [0.0, 1.0] {
      let id = try await store.start()
      _ = try await store.appendFrame(Data([1]), timestamp: timestamp, to: id)
      _ = try await store.stop(id, reason: .user)
      let preview = try await store.reservePreviewOutput(for: id)
      XCTAssertEqual(preview.maximumBytes, 90)
      try Data([71, 73, 70]).write(to: preview.url)
      _ = try await store.commitPreviewOutput(for: id, reservation: preview)
      sessionIDs.append(id)
    }

    let first = try await store.reserveCompressedPreviewOutput(for: sessionIDs[0])
    XCTAssertEqual(first.maximumBytes, 90)
    await assertThrowsSessionError(.insufficientDiskSpace) {
      _ = try await store.reserveCompressedPreviewOutput(for: sessionIDs[1])
    }
    try await store.abandonCompressedPreviewOutput(for: sessionIDs[0], reservation: first)
    let second = try await store.reserveCompressedPreviewOutput(for: sessionIDs[1])
    XCTAssertEqual(second.maximumBytes, 90)
    try await store.abandonCompressedPreviewOutput(for: sessionIDs[1], reservation: second)

    for id in sessionIDs {
      let snapshot = try await store.snapshot(for: id)
      XCTAssertEqual(snapshot.temporaryBytes, 4)
      try await store.discard(id)
    }
  }

  func testManagedCompressionReservesOutputAndCacheAndProtectsBothQuotas() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let store = SessionWorkspaceStore(
      rootDirectory: base.appendingPathComponent("sessions"),
      maximumSessionBytes: 20,
      minimumFreeBytes: 0,
      availableDiskBytesProvider: { 100 }
    )
    let id = try await store.start()
    _ = try await store.appendFrame(Data([1]), timestamp: 0, to: id)
    _ = try await store.stop(id, reason: .user)
    let preview = try await store.reservePreviewOutput(for: id)
    try Data([71, 73, 70]).write(to: preview.url)
    _ = try await store.commitPreviewOutput(for: id, reservation: preview)

    let compression = try await store.reserveCompressedPreviewOutput(
      for: id, sourceURL: preview.url, maximumCacheBytes: 4
    )
    XCTAssertEqual(compression.maximumCacheBytes, 4)
    XCTAssertEqual(compression.maximumBytes, 12)
    XCTAssertEqual(compression.sourceURL, preview.url.standardizedFileURL)
    let cacheDirectory = try XCTUnwrap(compression.cacheDirectory)
    XCTAssertTrue(FileManager.default.fileExists(atPath: cacheDirectory.path))
    var directoryInfo = stat()
    XCTAssertEqual(lstat(cacheDirectory.path, &directoryInfo), 0)
    XCTAssertEqual(directoryInfo.st_mode & 0o077, 0)

    try Data(repeating: 3, count: 4).write(
      to: cacheDirectory.appendingPathComponent("pixel-cache.bin")
    )
    try Data(repeating: 4, count: 5).write(to: compression.url)
    _ = try await store.commitCompressedPreviewOutput(for: id, reservation: compression)
    XCTAssertFalse(FileManager.default.fileExists(atPath: cacheDirectory.path))
    let committed = try await store.snapshot(for: id)
    XCTAssertEqual(committed.temporaryBytes, 9)
  }

  func testManagedCompressionReservationsAggregateOutputAndCacheAcrossSessions() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let store = SessionWorkspaceStore(
      rootDirectory: base.appendingPathComponent("sessions"),
      maximumSessionBytes: 1_024,
      minimumFreeBytes: 10,
      availableDiskBytesProvider: { 100 }
    )
    var sessions: [(RecordingSessionID, URL)] = []
    for timestamp in [0.0, 1.0] {
      let id = try await store.start()
      _ = try await store.appendFrame(Data([1]), timestamp: timestamp, to: id)
      _ = try await store.stop(id, reason: .user)
      let preview = try await store.reservePreviewOutput(for: id)
      try Data([71, 73, 70]).write(to: preview.url)
      _ = try await store.commitPreviewOutput(for: id, reservation: preview)
      sessions.append((id, preview.url))
    }

    let first = try await store.reserveCompressedPreviewOutput(
      for: sessions[0].0, sourceURL: sessions[0].1, maximumCacheBytes: 20
    )
    XCTAssertEqual(first.maximumBytes, 70)
    let recording = try await store.start()
    await assertThrowsSessionError(.insufficientDiskSpace) {
      _ = try await store.appendFrame(Data([9]), timestamp: 0, to: recording)
    }
    let unchangedRecording = try await store.snapshot(for: recording)
    XCTAssertEqual(unchangedRecording.frameCount, 0)
    XCTAssertEqual(unchangedRecording.temporaryBytes, 0)
    await assertThrowsSessionError(.insufficientDiskSpace) {
      _ = try await store.reserveCompressedPreviewOutput(
        for: sessions[1].0, sourceURL: sessions[1].1, maximumCacheBytes: 20
      )
    }
    try await store.abandonCompressedPreviewOutput(for: sessions[0].0, reservation: first)
    XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(first.cacheDirectory).path))

    let second = try await store.reserveCompressedPreviewOutput(
      for: sessions[1].0, sourceURL: sessions[1].1, maximumCacheBytes: 20
    )
    try await store.abandonCompressedPreviewOutput(for: sessions[1].0, reservation: second)
  }

  func testManagedCompressionRejectsOversizedCacheAndCleansRetryably() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let store = SessionWorkspaceStore(
      rootDirectory: base.appendingPathComponent("sessions"),
      maximumSessionBytes: 1_024,
      minimumFreeBytes: 0
    )
    let id = try await store.start()
    _ = try await store.appendFrame(Data([1]), timestamp: 0, to: id)
    _ = try await store.stop(id, reason: .user)
    let preview = try await store.reservePreviewOutput(for: id)
    try Data([71, 73, 70]).write(to: preview.url)
    _ = try await store.commitPreviewOutput(for: id, reservation: preview)
    let reservation = try await store.reserveCompressedPreviewOutput(
      for: id, sourceURL: preview.url, maximumCacheBytes: 4
    )
    let cacheDirectory = try XCTUnwrap(reservation.cacheDirectory)
    try Data(repeating: 2, count: 5).write(
      to: cacheDirectory.appendingPathComponent("pixel-cache.bin")
    )
    try Data([71, 73, 70]).write(to: reservation.url)

    await assertThrowsSessionError(.sizeLimitExceeded) {
      _ = try await store.commitCompressedPreviewOutput(for: id, reservation: reservation)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: cacheDirectory.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: reservation.url.path))
    let snapshot = try await store.snapshot(for: id)
    XCTAssertEqual(snapshot.temporaryBytes, 4)

    let retry = try await store.reserveCompressedPreviewOutput(
      for: id, sourceURL: preview.url, maximumCacheBytes: 4
    )
    try await store.abandonCompressedPreviewOutput(for: id, reservation: retry)
  }

  func testManagedCompressionRejectsUnaccountedSourceAndPreservesFreeSpaceFloor() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let store = SessionWorkspaceStore(
      rootDirectory: base.appendingPathComponent("sessions"),
      maximumSessionBytes: 1_024,
      minimumFreeBytes: 90,
      availableDiskBytesProvider: { 100 }
    )
    let id = try await store.start()
    _ = try await store.appendFrame(Data([1]), timestamp: 0, to: id)
    _ = try await store.stop(id, reason: .user)
    let preview = try await store.reservePreviewOutput(for: id)
    try Data([71, 73, 70]).write(to: preview.url)
    _ = try await store.commitPreviewOutput(for: id, reservation: preview)
    let external = base.appendingPathComponent("external.gif")
    try Data([71, 73, 70]).write(to: external)

    await assertThrowsSessionError(.invalidPreviewFile) {
      _ = try await store.reserveCompressedPreviewOutput(
        for: id, sourceURL: external, maximumCacheBytes: 1
      )
    }
    await assertThrowsSessionError(.insufficientDiskSpace) {
      _ = try await store.reserveCompressedPreviewOutput(
        for: id, sourceURL: preview.url, maximumCacheBytes: 10
      )
    }
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(
        atPath: preview.url.deletingLastPathComponent().path
      )
      .filter { $0.hasPrefix("compression-cache-") },
      []
    )
  }

  func testManagedCacheCleanupFailureRetainsReservationForRetry() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let root = base.appendingPathComponent("sessions", isDirectory: true)
    let store = SessionWorkspaceStore(
      rootDirectory: root, maximumSessionBytes: 1_024, minimumFreeBytes: 0
    )
    let id = try await store.start()
    _ = try await store.appendFrame(Data([1]), timestamp: 0, to: id)
    _ = try await store.stop(id, reason: .user)
    let preview = try await store.reservePreviewOutput(for: id)
    try Data([71, 73, 70]).write(to: preview.url)
    _ = try await store.commitPreviewOutput(for: id, reservation: preview)
    let reservation = try await store.reserveCompressedPreviewOutput(
      for: id, sourceURL: preview.url, maximumCacheBytes: 10
    )
    let cacheDirectory = try XCTUnwrap(reservation.cacheDirectory)
    let movedCache = base.appendingPathComponent("cache-backup", isDirectory: true)
    let outside = base.appendingPathComponent("outside", isDirectory: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: cacheDirectory, to: movedCache)
    try FileManager.default.createSymbolicLink(at: cacheDirectory, withDestinationURL: outside)

    await assertThrowsSessionError(.outputCleanupFailed) {
      try await store.abandonCompressedPreviewOutput(for: id, reservation: reservation)
    }
    await assertThrowsSessionError(.invalidState) {
      try await store.closePreviewAfterExport(id)
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: movedCache.path))
    try FileManager.default.removeItem(at: cacheDirectory)
    try FileManager.default.moveItem(at: movedCache, to: cacheDirectory)
    try await store.abandonCompressedPreviewOutput(for: id, reservation: reservation)
    XCTAssertFalse(FileManager.default.fileExists(atPath: cacheDirectory.path))
    try await store.closePreviewAfterExport(id)
  }

  func testFrameWritesRespectDiskCapacityReservedByAnotherSession() async throws {
    let base = uniqueTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let store = SessionWorkspaceStore(
      rootDirectory: base.appendingPathComponent("sessions"),
      maximumSessionBytes: 2_048,
      minimumFreeBytes: 10,
      availableDiskBytesProvider: { 100 }
    )
    let previewSession = try await store.start()
    _ = try await store.appendFrame(Data([1]), timestamp: 0, to: previewSession)
    _ = try await store.stop(previewSession, reason: .user)
    let preview = try await store.reservePreviewOutput(for: previewSession)
    try Data([71, 73, 70]).write(to: preview.url)
    _ = try await store.commitPreviewOutput(for: previewSession, reservation: preview)
    let compressed = try await store.reserveCompressedPreviewOutput(for: previewSession)

    let recordingSession = try await store.start()
    await assertThrowsSessionError(.insufficientDiskSpace) {
      _ = try await store.appendFrame(Data([2]), timestamp: 0, to: recordingSession)
    }
    let unchanged = try await store.snapshot(for: recordingSession)
    XCTAssertEqual(unchanged.frameCount, 0)
    XCTAssertEqual(unchanged.temporaryBytes, 0)

    try await store.abandonCompressedPreviewOutput(for: previewSession, reservation: compressed)
    let frame = try await store.appendFrame(Data([2]), timestamp: 0, to: recordingSession)
    XCTAssertTrue(FileManager.default.fileExists(atPath: frame.path))
    let appended = try await store.snapshot(for: recordingSession)
    XCTAssertEqual(appended.frameCount, 1)
    XCTAssertEqual(appended.temporaryBytes, 1)
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

  private func pngFrame() throws -> Data {
    try PNGFrameEncoder().encode(
      RecordingFrame(
        timestampNanoseconds: 1,
        width: 1,
        height: 1,
        bytesPerRow: 4,
        bgra: Data([0, 0, 255, 255])
      )
    )
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
