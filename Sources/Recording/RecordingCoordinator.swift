import Combine
import Foundation

@MainActor
protocol RecordingCaptureSession: AnyObject {
  var frames: AsyncStream<RecordingFrame> { get }
  func start() async throws
  func stop(reason: CaptureTerminationReason) async
}

@MainActor
protocol RecordingStreamPreparing {
  func prepare(
    target: RecordingTarget,
    showsCursor: Bool,
    onTermination: @escaping @MainActor (CaptureTerminationReason) -> Void
  ) async throws -> any RecordingCaptureSession
}

@MainActor
struct ScreenCaptureRecordingStreamFactory: RecordingStreamPreparing {
  let sourceService: CaptureSourceService

  init(sourceService: CaptureSourceService = CaptureSourceService()) {
    self.sourceService = sourceService
  }

  func prepare(
    target: RecordingTarget,
    showsCursor: Bool,
    onTermination: @escaping @MainActor (CaptureTerminationReason) -> Void
  ) async throws -> any RecordingCaptureSession {
    try await ScreenCaptureRecordingStream.prepare(
      target: target,
      showsCursor: showsCursor,
      sourceService: sourceService,
      onTermination: onTermination
    )
  }
}

enum RecordingCoordinatorFailure: Equatable {
  case permissionRequired
  case permissionLost
  case captureStartFailed
  case frameEncodingFailed
  case frameStorageFailed
  case streamFailed
  case workspaceFailed
  case noUsableFrames
  case cancelled
}

enum RecordingCoordinatorState: Equatable {
  case idle
  case starting
  case recording
  case stopping
  case captured(RecordingSessionID, RecordingSessionSnapshot)
  case failed(RecordingCoordinatorFailure)
}

/// serially turns captured frames into bounded, private PNG session files.
actor RecordingFramePipeline {
  private let sessionID: RecordingSessionID
  private let workspace: SessionWorkspaceStore
  private let encoder: PNGFrameEncoder

  init(
    sessionID: RecordingSessionID,
    workspace: SessionWorkspaceStore,
    encoder: PNGFrameEncoder = PNGFrameEncoder()
  ) {
    self.sessionID = sessionID
    self.workspace = workspace
    self.encoder = encoder
  }

  func consume(_ frames: AsyncStream<RecordingFrame>) async throws {
    for await frame in frames {
      try Task.checkCancellation()
      let png = try encoder.encode(frame)
      let timestamp = Double(frame.timestampNanoseconds) / 1_000_000_000
      _ = try await workspace.appendFrame(png, timestamp: timestamp, to: sessionID)
    }
  }
}

/// coordinates one capture, its sequential frame consumer, and workspace finalization.
@MainActor
final class RecordingCoordinator: ObservableObject {
  @Published private(set) var state: RecordingCoordinatorState = .idle

  private let streamFactory: any RecordingStreamPreparing
  private let workspace: SessionWorkspaceStore
  private let encoder: PNGFrameEncoder

  private var generation: UUID?
  private var startTask: Task<Void, Never>?
  private var stopTask: Task<Void, Never>?
  private var stream: (any RecordingCaptureSession)?
  private var consumerTask: Task<Void, Never>?
  private var sessionID: RecordingSessionID?
  private var stopReason: CaptureTerminationReason?
  private var consumerFailure: RecordingCoordinatorFailure?

  init(
    streamFactory: any RecordingStreamPreparing,
    workspace: SessionWorkspaceStore,
    encoder: PNGFrameEncoder = PNGFrameEncoder()
  ) {
    self.streamFactory = streamFactory
    self.workspace = workspace
    self.encoder = encoder
  }

  func cleanOrphanedSessions() async throws {
    try await workspace.cleanupOrphans()
  }

  /// returns after startup has either reached recording or failed.
  func start(target: RecordingTarget, showsCursor: Bool) async {
    guard canStart, startTask == nil, stopTask == nil, stream == nil, sessionID == nil else {
      return
    }
    let token = UUID()
    generation = token
    stopReason = nil
    consumerFailure = nil
    state = .starting
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.prepareAndStart(target: target, showsCursor: showsCursor, token: token)
    }
    startTask = task
    await task.value
    if generation == token {
      startTask = nil
    }
  }

  /// all callers share this task and observe completion only after frame drain and finalization.
  func stop(reason: CaptureTerminationReason = .userStopped) async {
    if let stopTask {
      await stopTask.value
      return
    }
    guard state == .starting || state == .recording || stream != nil || sessionID != nil else {
      return
    }

    stopReason = reason
    state = .stopping
    let startup = startTask
    startup?.cancel()
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await startup?.value
      await self.finish(reason: reason)
    }
    stopTask = task
    await task.value
    stopTask = nil
  }

  func discardCapturedSession() async {
    guard case .captured(let id, _) = state else { return }
    do {
      try await workspace.discard(id)
      sessionID = nil
      state = .idle
    } catch {
      state = .failed(.workspaceFailed)
    }
  }

  private func prepareAndStart(
    target: RecordingTarget,
    showsCursor: Bool,
    token: UUID
  ) async {
    do {
      try await workspace.cleanupOrphans()
      guard isCurrent(token), !Task.isCancelled else { throw CancellationError() }
      let id = try await workspace.start()
      sessionID = id
      let prepared = try await streamFactory.prepare(
        target: target,
        showsCursor: showsCursor,
        onTermination: { [weak self] reason in
          Task { @MainActor [weak self] in await self?.stop(reason: reason) }
        }
      )
      guard isCurrent(token), !Task.isCancelled else {
        await prepared.stop(reason: .userStopped)
        throw CancellationError()
      }

      stream = prepared
      let pipeline = RecordingFramePipeline(
        sessionID: id,
        workspace: workspace,
        encoder: encoder
      )
      // install the only consumer before starting ScreenCaptureKit.
      consumerTask = Task { @MainActor [weak self] in
        do {
          try await pipeline.consume(prepared.frames)
        } catch {
          guard let self, self.isCurrent(token) else { return }
          self.consumerFailure = Self.mapPipelineFailure(error)
          Task { @MainActor [weak self] in
            await self?.stop(reason: .streamFailed)
          }
        }
      }

      try await prepared.start()
      guard isCurrent(token), !Task.isCancelled else {
        return
      }
      state = .recording
    } catch is CancellationError {
      if generation == token {
        if let stream { await stream.stop(reason: .userStopped) }
        await consumerTask?.value
        await removeSessionIfPresent()
        clearActiveSession()
        state = .idle
      }
    } catch CaptureSourceError.permissionRequired {
      await failStartup(.permissionRequired, token: token)
    } catch {
      await failStartup(.captureStartFailed, token: token)
    }
  }

  private func failStartup(_ failure: RecordingCoordinatorFailure, token: UUID) async {
    guard generation == token else { return }
    if let stream { await stream.stop(reason: .streamFailed) }
    await consumerTask?.value
    await removeSessionIfPresent()
    clearActiveSession()
    state = .failed(failure)
  }

  private func finish(reason: CaptureTerminationReason) async {
    if let stream { await stream.stop(reason: reason) }
    await consumerTask?.value
    defer {
      clearActiveSession()
      generation = nil
    }

    if let consumerFailure {
      await removeSessionIfPresent()
      state = .failed(consumerFailure)
      return
    }

    guard let sessionID else {
      if case .failed = state { return }
      state = .idle
      return
    }

    guard let workspaceReason = Self.workspaceReason(for: reason) else {
      await removeSessionIfPresent()
      state = .failed(Self.failure(for: reason))
      return
    }
    do {
      let snapshot = try await workspace.stop(sessionID, reason: workspaceReason)
      state = .captured(sessionID, snapshot)
    } catch SessionWorkspaceError.noUsableFrames {
      state = .failed(.noUsableFrames)
    } catch {
      await removeSessionIfPresent()
      state = .failed(.workspaceFailed)
    }
  }

  private func removeSessionIfPresent() async {
    guard let sessionID else { return }
    try? await workspace.discard(sessionID)
  }

  private func clearActiveSession() {
    stream = nil
    consumerTask = nil
    sessionID = nil
    startTask = nil
    stopReason = nil
    consumerFailure = nil
  }

  private func isCurrent(_ token: UUID) -> Bool {
    generation == token
  }

  private var canStart: Bool {
    if case .idle = state { return true }
    if case .failed = state { return true }
    return false
  }

  private static func workspaceReason(
    for reason: CaptureTerminationReason
  ) -> RecordingStopReason? {
    switch reason {
    case .userStopped: .user
    case .windowUnavailable: .windowUnavailable
    case .displayDisconnected: .displayUnavailable
    case .permissionLost, .streamFailed: nil
    }
  }

  private static func failure(for reason: CaptureTerminationReason) -> RecordingCoordinatorFailure {
    switch reason {
    case .permissionLost: .permissionLost
    case .streamFailed: .streamFailed
    case .userStopped, .windowUnavailable, .displayDisconnected: .noUsableFrames
    }
  }

  private static func mapPipelineFailure(_ error: Error) -> RecordingCoordinatorFailure {
    if error is PNGFrameEncodingError { return .frameEncodingFailed }
    if error is SessionWorkspaceError { return .frameStorageFailed }
    return .frameStorageFailed
  }
}
