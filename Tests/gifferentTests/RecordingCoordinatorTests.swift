import Foundation
import XCTest

@testable import gifferent

@MainActor
final class RecordingCoordinatorTests: XCTestCase {
  func testFirstFrameDeliveredImmediatelyAfterStartIsPersisted() async throws {
    let fixture = makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let stream = FakeRecordingStream(framesOnStart: [validFrame(at: 1)])
    let factory = FakeRecordingStreamFactory(stream: stream)
    let coordinator = RecordingCoordinator(streamFactory: factory, workspace: fixture.workspace)

    await coordinator.start(target: .display(1), showsCursor: true)
    XCTAssertEqual(coordinator.state, .recording)
    await coordinator.stop()
    await waitForPreview(coordinator)

    guard case .previewReady(_, let snapshot, let gif) = coordinator.state else {
      return XCTFail("expected a validated gif preview")
    }
    XCTAssertEqual(snapshot.frameCount, 1)
    XCTAssertGreaterThan(snapshot.temporaryBytes, 0)
    XCTAssertEqual(gif.frameCount, 1)
    XCTAssertEqual(gif.width, 1)
  }

  func testStartFailureCleansWorkspaceAndAllowsRetry() async throws {
    let fixture = makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let stream = FakeRecordingStream(startError: TestFailure.start)
    let retryStream = FakeRecordingStream()
    let factory = FakeRecordingStreamFactory(streams: [stream, retryStream])
    let coordinator = RecordingCoordinator(streamFactory: factory, workspace: fixture.workspace)

    await coordinator.start(target: .display(1), showsCursor: true)
    XCTAssertEqual(coordinator.state, .failed(.captureStartFailed))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path), [])
    XCTAssertEqual(stream.stopCalls, 1)

    await coordinator.start(target: .display(1), showsCursor: true)
    XCTAssertEqual(coordinator.state, .recording)
    await coordinator.stop()
  }

  func testDuplicateStartDoesNotCreateAnotherStreamOrWorkspace() async throws {
    let fixture = makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let stream = FakeRecordingStream(startGate: true)
    let factory = FakeRecordingStreamFactory(stream: stream)
    let coordinator = RecordingCoordinator(streamFactory: factory, workspace: fixture.workspace)

    let firstStart = Task { await coordinator.start(target: .display(1), showsCursor: true) }
    while !stream.waitingForStart { await Task.yield() }
    await coordinator.start(target: .display(1), showsCursor: true)
    XCTAssertEqual(factory.prepareCalls, 1)
    stream.resumeStart()
    await firstStart.value
    XCTAssertEqual(coordinator.state, .recording)
    await coordinator.stop()
  }

  func testCapturedWorkspaceBlocksNewStartUntilDiscarded() async throws {
    let fixture = makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let firstStream = FakeRecordingStream(framesOnStart: [validFrame(at: 1)])
    let secondStream = FakeRecordingStream()
    let factory = FakeRecordingStreamFactory(streams: [firstStream, secondStream])
    let coordinator = RecordingCoordinator(streamFactory: factory, workspace: fixture.workspace)
    await coordinator.start(target: .display(1), showsCursor: false)
    await coordinator.stop()
    await waitForPreview(coordinator)

    await coordinator.start(target: .display(1), showsCursor: false)
    XCTAssertEqual(factory.prepareCalls, 1)
    guard case .previewReady = coordinator.state else {
      return XCTFail("expected retained preview session")
    }

    await coordinator.discardCapturedSession()
    XCTAssertEqual(coordinator.state, .idle)
    await coordinator.start(target: .display(1), showsCursor: false)
    XCTAssertEqual(factory.prepareCalls, 2)
    await coordinator.stop()
  }

  func testStopDrainsAllAcceptedFramesBeforePublishingCapturedState() async throws {
    let fixture = makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let stream = FakeRecordingStream(
      framesOnStart: (1...3).map { validFrame(at: Int64($0) * 50_000_000) })
    let coordinator = RecordingCoordinator(
      streamFactory: FakeRecordingStreamFactory(stream: stream),
      workspace: fixture.workspace
    )

    await coordinator.start(target: .display(1), showsCursor: false)
    await coordinator.stop()
    await waitForPreview(coordinator)

    guard case .previewReady(_, let snapshot, _) = coordinator.state else {
      return XCTFail("expected a validated preview")
    }
    XCTAssertEqual(snapshot.frameCount, 3)
    XCTAssertEqual(stream.stopCalls, 1)
  }

  func testNewestEditRequestWinsAndClipboardUsesTheEditedGIF() async throws {
    let fixture = makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let encoder = GatedEditGIFEncoder()
    let clipboard = RecordingTestClipboard()
    let coordinator = RecordingCoordinator(
      streamFactory: FakeRecordingStreamFactory(
        stream: FakeRecordingStream(
          framesOnStart: [
            validFrame(at: 100_000_000),
            validFrame(at: 200_000_000),
            validFrame(at: 300_000_000),
          ])),
      workspace: fixture.workspace,
      gifEncoder: encoder,
      clipboard: clipboard
    )
    await coordinator.start(target: .display(1), showsCursor: false)
    await coordinator.stop()
    await waitForPreview(coordinator)

    guard case .previewReady(_, _, let original) = coordinator.state else {
      return XCTFail("expected the original preview")
    }
    coordinator.updateTrim(startIndex: 0, endIndexExclusive: 2)
    while !(await encoder.isWaitingForEdit()) { await Task.yield() }
    XCTAssertTrue(coordinator.isPreviewUpdateInProgress)
    await coordinator.copyPreview()
    XCTAssertTrue(clipboard.urls.isEmpty)

    coordinator.updatePlaybackSpeed(1.5)
    coordinator.updateLoopMode(.once)
    await waitUntil(timeout: .seconds(5)) { !coordinator.isPreviewUpdateInProgress }

    guard case .previewReady(_, _, let edited) = coordinator.state else {
      return XCTFail("expected an edited preview")
    }
    XCTAssertEqual(edited.frameCount, 2)
    XCTAssertFalse(edited.loopsForever)
    XCTAssertNotEqual(edited.url, original.url)
    XCTAssertTrue(FileManager.default.fileExists(atPath: original.url.path))
    XCTAssertEqual(
      coordinator.editParameters?.frameRange, GIFFrameRange(startIndex: 0, endIndexExclusive: 2))
    XCTAssertEqual(coordinator.editParameters?.playbackSpeed, 1.5)
    XCTAssertEqual(coordinator.editParameters?.loopMode, .once)

    await coordinator.copyPreview()
    XCTAssertEqual(clipboard.urls, [edited.url])
    let closed = await coordinator.closePreview(discardUnexported: false)
    XCTAssertTrue(closed)
    XCTAssertFalse(FileManager.default.fileExists(atPath: clipboard.urls[0].path))
  }

  func testConcurrentStopCallersAwaitOneFinalization() async throws {
    let fixture = makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let stream = FakeRecordingStream(
      framesOnStart: [validFrame(at: 1)], stopDelay: .milliseconds(80))
    let coordinator = RecordingCoordinator(
      streamFactory: FakeRecordingStreamFactory(stream: stream),
      workspace: fixture.workspace
    )
    await coordinator.start(target: .display(1), showsCursor: false)

    async let first: Void = coordinator.stop()
    async let second: Void = coordinator.stop(reason: .windowUnavailable)
    _ = await (first, second)
    await waitForPreview(coordinator)

    XCTAssertEqual(stream.stopCalls, 1)
    guard case .previewReady(_, let snapshot, _) = coordinator.state else {
      return XCTFail("expected a validated preview")
    }
    XCTAssertEqual(snapshot.frameCount, 1)
  }

  func testEncoderFailureStopsAndRemovesSession() async throws {
    let fixture = makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let stream = FakeRecordingStream(framesOnStart: [invalidFrame(at: 1)])
    let coordinator = RecordingCoordinator(
      streamFactory: FakeRecordingStreamFactory(stream: stream),
      workspace: fixture.workspace
    )

    await coordinator.start(target: .display(1), showsCursor: false)
    await waitUntil {
      if case .failed(.frameEncodingFailed) = coordinator.state { true } else { false }
    }

    XCTAssertEqual(stream.stopCalls, 1)
    XCTAssertEqual(coordinator.state, .failed(.frameEncodingFailed))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path), [])
  }

  func testStorageFailureStopsAndRemovesSession() async throws {
    let fixture = makeFixture(maximumBytes: 1)
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let stream = FakeRecordingStream(framesOnStart: [validFrame(at: 1)])
    let coordinator = RecordingCoordinator(
      streamFactory: FakeRecordingStreamFactory(stream: stream),
      workspace: fixture.workspace
    )

    await coordinator.start(target: .display(1), showsCursor: false)
    await waitUntil { coordinator.state == .failed(.frameStorageFailed) }

    XCTAssertEqual(stream.stopCalls, 1)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path), [])
  }

  func testEmptyStopFailsAndCleansSession() async throws {
    let fixture = makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let stream = FakeRecordingStream()
    let coordinator = RecordingCoordinator(
      streamFactory: FakeRecordingStreamFactory(stream: stream),
      workspace: fixture.workspace
    )
    await coordinator.start(target: .display(1), showsCursor: false)
    await coordinator.stop()

    XCTAssertEqual(coordinator.state, .failed(.noUsableFrames))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path), [])
  }

  func testWindowAndDisplayLossRetainPartialFrames() async throws {
    for (reason, expected) in [
      (CaptureTerminationReason.windowUnavailable, RecordingStopReason.windowUnavailable),
      (.displayDisconnected, .displayUnavailable),
    ] {
      let fixture = makeFixture()
      let stream = FakeRecordingStream(framesOnStart: [validFrame(at: 1)])
      let coordinator = RecordingCoordinator(
        streamFactory: FakeRecordingStreamFactory(stream: stream),
        workspace: fixture.workspace
      )
      await coordinator.start(target: .display(1), showsCursor: false)
      await coordinator.stop(reason: reason)
      await waitForPreview(coordinator)

      guard case .previewReady(_, let snapshot, _) = coordinator.state else {
        return XCTFail("expected partial capture")
      }
      XCTAssertEqual(snapshot.stopReason, expected)
      XCTAssertTrue(snapshot.isPartialResult)
      try? FileManager.default.removeItem(at: fixture.base)
    }
  }

  func testPermissionLossAndStreamFailureAreErrorsEvenWithFrames() async throws {
    for reason in [CaptureTerminationReason.permissionLost, .streamFailed] {
      let fixture = makeFixture()
      let stream = FakeRecordingStream(framesOnStart: [validFrame(at: 1)])
      let coordinator = RecordingCoordinator(
        streamFactory: FakeRecordingStreamFactory(stream: stream),
        workspace: fixture.workspace
      )
      await coordinator.start(target: .display(1), showsCursor: false)
      await coordinator.stop(reason: reason)

      let expected: RecordingCoordinatorFailure =
        reason == .permissionLost
        ? .permissionLost : .streamFailed
      XCTAssertEqual(coordinator.state, .failed(expected))
      XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path), [])
      try? FileManager.default.removeItem(at: fixture.base)
    }
  }

  func testEncodingFailureRetainsFramesAndRetryProducesPreview() async throws {
    let fixture = makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let encoder = FailFirstGIFEncoder()
    let coordinator = RecordingCoordinator(
      streamFactory: FakeRecordingStreamFactory(
        stream: FakeRecordingStream(framesOnStart: [validFrame(at: 1)])),
      workspace: fixture.workspace,
      gifEncoder: encoder
    )
    await coordinator.start(target: .display(1), showsCursor: false)
    await coordinator.stop()
    await waitUntil(timeout: .seconds(5)) {
      if case .captured = coordinator.state {
        coordinator.previewAction == .failed
      } else {
        false
      }
    }
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).count, 1)

    coordinator.retryPreviewEncoding()
    await waitForPreview(coordinator)
    guard case .previewReady(_, let snapshot, let gif) = coordinator.state else {
      return XCTFail("expected retry to produce a preview")
    }
    XCTAssertEqual(snapshot.frameCount, 1)
    XCTAssertEqual(gif.frameCount, 1)
    let discarded = await coordinator.closePreview(discardUnexported: true)
    XCTAssertTrue(discarded)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path), [])
  }

  func testInvalidEncodedMetadataKeepsCapturedFramesDiscardable() async throws {
    let fixture = makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let coordinator = RecordingCoordinator(
      streamFactory: FakeRecordingStreamFactory(
        stream: FakeRecordingStream(framesOnStart: [validFrame(at: 1)])),
      workspace: fixture.workspace,
      gifEncoder: MismatchedMetadataGIFEncoder()
    )
    await coordinator.start(target: .display(1), showsCursor: false)
    await coordinator.stop()
    await waitUntil(timeout: .seconds(5)) {
      if case .captured = coordinator.state {
        coordinator.previewAction == .failed
      } else {
        false
      }
    }
    let closeWithoutDiscard = await coordinator.closePreview(discardUnexported: false)
    XCTAssertFalse(closeWithoutDiscard)
    let discarded = await coordinator.closePreview(discardUnexported: true)
    XCTAssertTrue(discarded)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path), [])
  }

  func testCopyFailureAndSaveCancellationKeepPreviewAndRequireDiscard() async throws {
    let fixture = makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let clipboard = CoordinatorTestClipboard(shouldFail: true)
    let saver = CoordinatorTestSaver(result: .cancelled)
    let coordinator = RecordingCoordinator(
      streamFactory: FakeRecordingStreamFactory(
        stream: FakeRecordingStream(framesOnStart: [validFrame(at: 1)])),
      workspace: fixture.workspace,
      clipboard: clipboard,
      fileSaver: saver
    )
    await coordinator.start(target: .display(1), showsCursor: false)
    await coordinator.stop()
    await waitForPreview(coordinator)

    await coordinator.copyPreview()
    XCTAssertEqual(coordinator.previewAction, .failed)
    await coordinator.savePreview()
    XCTAssertEqual(coordinator.previewAction, .cancelled)
    let closeWithoutDiscard = await coordinator.closePreview(discardUnexported: false)
    XCTAssertFalse(closeWithoutDiscard)
    guard case .previewReady = coordinator.state else {
      return XCTFail("expected preview to remain available")
    }
    let discarded = await coordinator.closePreview(discardUnexported: true)
    XCTAssertTrue(discarded)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path), [])
  }

  func testSuccessfulSaveKeepsExportAfterPreviewCleanup() async throws {
    let fixture = makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let exported = fixture.base.appendingPathComponent("saved.gif")
    let saver = CoordinatorTestSaver(destination: exported)
    let coordinator = RecordingCoordinator(
      streamFactory: FakeRecordingStreamFactory(
        stream: FakeRecordingStream(framesOnStart: [validFrame(at: 1)])),
      workspace: fixture.workspace,
      fileSaver: saver
    )
    await coordinator.start(target: .display(1), showsCursor: false)
    await coordinator.stop()
    await waitForPreview(coordinator)
    await coordinator.savePreview()
    XCTAssertEqual(coordinator.previewAction, .saved)
    let closed = await coordinator.closePreview(discardUnexported: false)
    XCTAssertTrue(closed)
    XCTAssertTrue(FileManager.default.fileExists(atPath: exported.path))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path), [])
  }

  func testPreviewCannotBeClosedWhileCopyIsInProgress() async throws {
    let fixture = makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let clipboard = BlockingCoordinatorTestClipboard()
    let coordinator = RecordingCoordinator(
      streamFactory: FakeRecordingStreamFactory(
        stream: FakeRecordingStream(framesOnStart: [validFrame(at: 1)])),
      workspace: fixture.workspace,
      clipboard: clipboard
    )
    await coordinator.start(target: .display(1), showsCursor: false)
    await coordinator.stop()
    await waitForPreview(coordinator)

    let copy = Task { await coordinator.copyPreview() }
    while !clipboard.isWaiting { await Task.yield() }
    XCTAssertTrue(coordinator.isPreviewActionInProgress)
    let closedDuringCopy = await coordinator.closePreview(discardUnexported: true)
    XCTAssertFalse(closedDuringCopy)
    guard case .previewReady = coordinator.state else {
      return XCTFail("preview must remain available while copy is in progress")
    }
    guard case .previewReady(_, _, let gif) = coordinator.state else {
      return XCTFail("expected preview media to remain while copy is in progress")
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: gif.url.path))

    clipboard.resume()
    await copy.value
    XCTAssertEqual(coordinator.previewAction, .copied)
    let closedAfterCopy = await coordinator.closePreview(discardUnexported: false)
    XCTAssertTrue(closedAfterCopy)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path), [])
  }

  func testPreviewCannotBeDiscardedWhileSaveIsInProgress() async throws {
    let fixture = makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let saver = BlockingCoordinatorTestSaver()
    let coordinator = RecordingCoordinator(
      streamFactory: FakeRecordingStreamFactory(
        stream: FakeRecordingStream(framesOnStart: [validFrame(at: 1)])),
      workspace: fixture.workspace,
      fileSaver: saver
    )
    await coordinator.start(target: .display(1), showsCursor: false)
    await coordinator.stop()
    await waitForPreview(coordinator)

    let save = Task { await coordinator.savePreview() }
    while !saver.isWaiting { await Task.yield() }
    XCTAssertTrue(coordinator.isPreviewActionInProgress)
    let discardedDuringSave = await coordinator.closePreview(discardUnexported: true)
    XCTAssertFalse(discardedDuringSave)
    guard case .previewReady(_, _, let gif) = coordinator.state else {
      return XCTFail("preview must remain available while save is in progress")
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: gif.url.path))

    saver.resume()
    await save.value
    XCTAssertEqual(coordinator.previewAction, .saved)
    let closedAfterSave = await coordinator.closePreview(discardUnexported: false)
    XCTAssertTrue(closedAfterSave)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path), [])
  }

  private func makeFixture(maximumBytes: Int64 = 1_000_000) -> (
    base: URL, root: URL, workspace: SessionWorkspaceStore
  ) {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let root = base.appendingPathComponent("sessions", isDirectory: true)
    return (
      base,
      root,
      SessionWorkspaceStore(
        rootDirectory: root, maximumSessionBytes: maximumBytes, minimumFreeBytes: 0)
    )
  }

  private func validFrame(at timestamp: Int64) -> RecordingFrame {
    RecordingFrame(
      timestampNanoseconds: timestamp,
      width: 1,
      height: 1,
      bytesPerRow: 4,
      bgra: Data([0, 0, 0, 255])
    )
  }

  private func invalidFrame(at timestamp: Int64) -> RecordingFrame {
    RecordingFrame(
      timestampNanoseconds: timestamp,
      width: 1,
      height: 1,
      bytesPerRow: 4,
      bgra: Data([0])
    )
  }

  private func waitUntil(
    timeout: Duration = .seconds(2),
    condition: @MainActor () -> Bool
  ) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(10))
    }
  }

  private func waitForPreview(_ coordinator: RecordingCoordinator) async {
    await waitUntil(timeout: .seconds(5)) {
      if case .previewReady = coordinator.state { true } else { false }
    }
  }
}

private enum TestFailure: Error { case start }

@MainActor
private final class RecordingTestClipboard: GIFClipboardWriting {
  private(set) var urls: [URL] = []

  func writeGIF(at url: URL) async throws {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw CocoaError(.fileNoSuchFile)
    }
    urls.append(url)
  }
}

private actor GatedEditGIFEncoder: OriginalGIFEncoding {
  private let encoder = ImageIOOriginalGIFEncoder()
  private var waitingForEdit = false
  private var didWaitForEdit = false

  func isWaitingForEdit() -> Bool { waitingForEdit }

  func encode(
    _ sequence: CapturedPNGSequence,
    to reservation: PreviewOutputReservation
  ) async throws -> EncodedGIF {
    try await encode(sequence, loopMode: .forever, to: reservation)
  }

  func encode(
    _ sequence: CapturedPNGSequence,
    loopMode: GIFLoopMode,
    to reservation: PreviewOutputReservation
  ) async throws -> EncodedGIF {
    if sequence.frames.count == 2, !didWaitForEdit {
      didWaitForEdit = true
      waitingForEdit = true
      do {
        try await Task.sleep(for: .seconds(30))
      } catch {
        waitingForEdit = false
        throw OriginalGIFEncodingError.cancelled
      }
      waitingForEdit = false
    }
    return try await encoder.encode(sequence, loopMode: loopMode, to: reservation)
  }
}

@MainActor
private final class FakeRecordingStreamFactory: RecordingStreamPreparing {
  private let streams: [FakeRecordingStream]
  private(set) var prepareCalls = 0

  convenience init(stream: FakeRecordingStream) { self.init(streams: [stream]) }

  init(streams: [FakeRecordingStream]) { self.streams = streams }

  func prepare(
    target: RecordingTarget,
    showsCursor: Bool,
    onTermination _: @escaping @MainActor (CaptureTerminationReason) -> Void
  ) async throws -> any RecordingCaptureSession {
    let stream = streams[min(prepareCalls, streams.count - 1)]
    prepareCalls += 1
    return stream
  }
}

@MainActor
private final class FakeRecordingStream: RecordingCaptureSession {
  let transport = RecordingFrameTransport()
  var frames: AsyncStream<RecordingFrame> { transport.frames }
  var startError: Error?
  var startGate: Bool
  var stopDelay: Duration
  private(set) var stopCalls = 0
  private(set) var waitingForStart = false
  private var startContinuation: CheckedContinuation<Void, Never>?

  init(
    framesOnStart: [RecordingFrame] = [],
    startError: Error? = nil,
    startGate: Bool = false,
    stopDelay: Duration = .zero
  ) {
    self.startError = startError
    self.startGate = startGate
    self.stopDelay = stopDelay
    self.framesOnStart = framesOnStart
  }

  private let framesOnStart: [RecordingFrame]

  func start() async throws {
    if startGate {
      waitingForStart = true
      await withCheckedContinuation { startContinuation = $0 }
      waitingForStart = false
    }
    if let startError { throw startError }
    for frame in framesOnStart { transport.offer(frame) }
  }

  func stop(reason: CaptureTerminationReason) async {
    stopCalls += 1
    if stopDelay > .zero { try? await Task.sleep(for: stopDelay) }
    transport.finish()
  }

  func resumeStart() {
    startContinuation?.resume()
    startContinuation = nil
  }
}

private actor FailFirstGIFEncoder: OriginalGIFEncoding {
  private var shouldFail = true

  func encode(
    _ sequence: CapturedPNGSequence,
    to reservation: PreviewOutputReservation
  ) async throws -> EncodedGIF {
    if shouldFail {
      shouldFail = false
      throw OriginalGIFEncodingError.encodingFailed
    }
    return try await ImageIOOriginalGIFEncoder().encode(sequence, to: reservation)
  }
}

private actor MismatchedMetadataGIFEncoder: OriginalGIFEncoding {
  func encode(
    _ sequence: CapturedPNGSequence,
    to reservation: PreviewOutputReservation
  ) async throws -> EncodedGIF {
    let actual = try await ImageIOOriginalGIFEncoder().encode(sequence, to: reservation)
    return EncodedGIF(
      url: actual.url,
      width: actual.width,
      height: actual.height,
      frameCount: actual.frameCount + 1,
      delaysCentiseconds: actual.delaysCentiseconds,
      durationCentiseconds: actual.durationCentiseconds,
      loopsForever: actual.loopsForever,
      fileBytes: actual.fileBytes
    )
  }
}

@MainActor
private final class CoordinatorTestClipboard: GIFClipboardWriting {
  let shouldFail: Bool
  private(set) var writeCount = 0

  init(shouldFail: Bool = false) {
    self.shouldFail = shouldFail
  }

  func writeGIF(at url: URL) async throws {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw CocoaError(.fileReadNoSuchFile)
    }
    writeCount += 1
    if shouldFail { throw NSError(domain: "gifferent.test.clipboard", code: 1) }
  }
}

@MainActor
private final class BlockingCoordinatorTestClipboard: GIFClipboardWriting {
  private(set) var isWaiting = false
  private var continuation: CheckedContinuation<Void, Never>?

  func writeGIF(at url: URL) async throws {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw CocoaError(.fileReadNoSuchFile)
    }
    isWaiting = true
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func resume() {
    continuation?.resume()
    continuation = nil
  }
}

@MainActor
private final class BlockingCoordinatorTestSaver: GIFSaving {
  private(set) var isWaiting = false
  private var continuation: CheckedContinuation<Void, Never>?

  func saveGIF(at url: URL) async throws -> PreviewSaveResult {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw CocoaError(.fileReadNoSuchFile)
    }
    isWaiting = true
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
    return .saved
  }

  func resume() {
    continuation?.resume()
    continuation = nil
  }
}

@MainActor
private final class CoordinatorTestSaver: GIFSaving {
  private let destination: URL?
  private let result: PreviewSaveResult

  init(result: PreviewSaveResult) {
    destination = nil
    self.result = result
  }

  init(destination: URL) {
    self.destination = destination
    result = .saved
  }

  func saveGIF(at url: URL) async throws -> PreviewSaveResult {
    guard let destination else { return result }
    try FileManager.default.copyItem(at: url, to: destination)
    return .saved
  }
}
