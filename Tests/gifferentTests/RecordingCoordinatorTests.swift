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

    guard case .captured(_, let snapshot) = coordinator.state else {
      return XCTFail("expected captured session")
    }
    XCTAssertEqual(snapshot.frameCount, 1)
    XCTAssertGreaterThan(snapshot.temporaryBytes, 0)
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

    await coordinator.start(target: .display(1), showsCursor: false)
    XCTAssertEqual(factory.prepareCalls, 1)
    guard case .captured = coordinator.state else {
      return XCTFail("expected retained captured session")
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
    let stream = FakeRecordingStream(framesOnStart: (1...3).map { validFrame(at: Int64($0)) })
    let coordinator = RecordingCoordinator(
      streamFactory: FakeRecordingStreamFactory(stream: stream),
      workspace: fixture.workspace
    )

    await coordinator.start(target: .display(1), showsCursor: false)
    await coordinator.stop()

    guard case .captured(_, let snapshot) = coordinator.state else {
      return XCTFail("expected captured session")
    }
    XCTAssertEqual(snapshot.frameCount, 3)
    XCTAssertEqual(stream.stopCalls, 1)
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

    XCTAssertEqual(stream.stopCalls, 1)
    guard case .captured(_, let snapshot) = coordinator.state else {
      return XCTFail("expected captured session")
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

      guard case .captured(_, let snapshot) = coordinator.state else {
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
}

private enum TestFailure: Error { case start }

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
