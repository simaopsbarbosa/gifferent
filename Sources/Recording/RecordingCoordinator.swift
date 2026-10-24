import Combine
import Foundation

struct RecordingWorkspaceByteUpdateThrottle {
  private let minimumInterval: Duration
  private(set) var lastUpdate: ContinuousClock.Instant?

  init(minimumInterval: Duration = .milliseconds(250)) {
    self.minimumInterval = minimumInterval
  }

  mutating func shouldPublish(at now: ContinuousClock.Instant) -> Bool {
    guard let lastUpdate else {
      self.lastUpdate = now
      return true
    }
    guard now - lastUpdate >= minimumInterval else { return false }
    self.lastUpdate = now
    return true
  }
}

@MainActor
protocol RecordingCaptureSession: AnyObject {
  var frames: AsyncStream<RecordingFrame> { get }
  var frameStatistics: RecordingFrameStatistics { get }
  func start() async throws
  func stop(reason: CaptureTerminationReason) async
}

extension RecordingCaptureSession {
  var frameStatistics: RecordingFrameStatistics {
    RecordingFrameStatistics(accepted: 0, dropped: 0, rejectedTimestamps: 0)
  }
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
  case gifEncodingFailed
}

enum RecordingCoordinatorState: Equatable {
  case idle
  case starting
  case recording
  case stopping
  case captured(RecordingSessionID, RecordingSessionSnapshot)
  case preparingPreview(RecordingSessionID, RecordingSessionSnapshot)
  case previewReady(RecordingSessionID, RecordingSessionSnapshot, EncodedGIF)
  case failed(RecordingCoordinatorFailure)
}

enum PreviewSaveResult: Equatable, Sendable {
  case saved
  case cancelled
}

@MainActor
protocol GIFClipboardWriting {
  func writeGIF(at url: URL) async throws
}

@MainActor
protocol GIFSaving {
  func saveGIF(at url: URL) async throws -> PreviewSaveResult
}

enum PreviewAction: Equatable {
  case idle
  case updated
  case updateFailed
  case copying
  case saving
  case copied
  case saved
  case cancelled
  case failed
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

  func consume(
    _ frames: AsyncStream<RecordingFrame>,
    onStoredBytes: @MainActor (Int64) -> Void
  ) async throws {
    var storedBytes: Int64 = 0
    let clock = ContinuousClock()
    var byteUpdateThrottle = RecordingWorkspaceByteUpdateThrottle()
    for await frame in frames {
      try Task.checkCancellation()
      let png = try encoder.encode(frame)
      let timestamp = Double(frame.timestampNanoseconds) / 1_000_000_000
      _ = try await workspace.appendFrame(png, timestamp: timestamp, to: sessionID)
      storedBytes += Int64(png.count)
      if byteUpdateThrottle.shouldPublish(at: clock.now) {
        await onStoredBytes(storedBytes)
      }
    }
  }
}

/// coordinates one capture, its sequential frame consumer, and workspace finalization.
@MainActor
final class RecordingCoordinator: ObservableObject {
  @Published private(set) var state: RecordingCoordinatorState = .idle
  private(set) var diagnostics = RecordingDiagnostics()
  @Published private(set) var previewAction: PreviewAction = .idle
  @Published private(set) var editParameters: GIFEditParameters?
  @Published private(set) var isPreviewUpdateInProgress = false
  @Published private(set) var editFrameCount = 0
  @Published private(set) var recordingWorkspaceBytes: Int64 = 0
  @Published private(set) var compressionSettings = GIFCompressionSettings()
  @Published private(set) var compressionAction: GIFCompressionAction
  @Published private(set) var compressedPreview: EncodedGIF?

  #if DEBUG
    func setRecordingWorkspaceBytesFixture(_ bytes: Int64) {
      recordingWorkspaceBytes = max(0, bytes)
    }
  #endif

  private let streamFactory: any RecordingStreamPreparing
  private let workspace: SessionWorkspaceStore
  private let encoder: PNGFrameEncoder
  private let gifEncoder: any OriginalGIFEncoding
  private let compressor: (any GIFCompressing)?
  private let clipboard: any GIFClipboardWriting
  private let fileSaver: any GIFSaving
  private let diagnosticsClock: any RecordingDiagnosticsClock

  private var generation: UUID?
  private var startTask: Task<Void, Never>?
  private var stopTask: Task<Void, Never>?
  private var stream: (any RecordingCaptureSession)?
  private var consumerTask: Task<Void, Never>?
  private var sessionID: RecordingSessionID?
  private var stopReason: CaptureTerminationReason?
  private var consumerFailure: RecordingCoordinatorFailure?
  private var previewTask: Task<Void, Never>?
  private var replacementTask: Task<Void, Never>?
  private var compressionTask: Task<Void, Never>?
  private var compressionRequest: UUID?
  private var latestEditRequest: UUID?
  private var originalSequence: CapturedPNGSequence?
  private var currentPreviewParameters: GIFEditParameters?
  private var previewExported = false
  private var originalPreviewExportedBeforeCompression: Bool?
  private var recordingRequestedAt: Duration?
  private var stopRequestedAt: Duration?

  init(
    streamFactory: any RecordingStreamPreparing,
    workspace: SessionWorkspaceStore,
    encoder: PNGFrameEncoder = PNGFrameEncoder(),
    gifEncoder: any OriginalGIFEncoding = ImageIOOriginalGIFEncoder(),
    compressor: (any GIFCompressing)? = nil,
    clipboard: any GIFClipboardWriting = NSPasteboardGIFWriter(),
    fileSaver: any GIFSaving = SavePanelGIFSaver(),
    diagnosticsClock: any RecordingDiagnosticsClock = SystemRecordingDiagnosticsClock()
  ) {
    self.streamFactory = streamFactory
    self.workspace = workspace
    self.encoder = encoder
    self.gifEncoder = gifEncoder
    self.compressor = compressor
    compressionAction = compressor == nil ? .unavailable : .idle
    self.clipboard = clipboard
    self.fileSaver = fileSaver
    self.diagnosticsClock = diagnosticsClock
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
    diagnostics = RecordingDiagnostics()
    recordingWorkspaceBytes = 0
    recordingRequestedAt = diagnosticsClock.now()
    stopRequestedAt = nil
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
    if stopRequestedAt == nil {
      stopRequestedAt = diagnosticsClock.now()
    }
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
    guard !isPreviewActionInProgress else { return }
    let id: RecordingSessionID
    switch state {
    case .captured(let capturedID, _), .preparingPreview(let capturedID, _),
      .previewReady(let capturedID, _, _):
      id = capturedID
      previewTask?.cancel()
      await previewTask?.value
      previewTask = nil
    default:
      return
    }
    await cancelPreviewReplacement()
    do {
      try await workspace.discard(id)
      sessionID = nil
      previewExported = false
      originalPreviewExportedBeforeCompression = nil
      compressedPreview = nil
      compressionAction = isCompressionAvailable ? .idle : .unavailable
      editParameters = nil
      currentPreviewParameters = nil
      originalSequence = nil
      editFrameCount = 0
      state = .idle
    } catch {
      if case .preparingPreview(_, let snapshot) = state {
        state = .captured(id, snapshot)
      }
      previewAction = .failed
    }
  }

  var isPreviewActionInProgress: Bool {
    previewAction == .copying || previewAction == .saving || isCompressionInProgress
  }

  func retryPreviewEncoding() {
    guard case .captured(let id, let snapshot) = state, previewTask == nil else { return }
    previewTask = Task { @MainActor [weak self] in
      await self?.preparePreview(sessionID: id, snapshot: snapshot)
    }
  }

  func updateTrim(startIndex: Int, endIndexExclusive: Int) {
    guard compressedPreview == nil, !isCompressionInProgress else { return }
    guard var parameters = editParameters else { return }
    parameters.frameRange = GIFFrameRange(
      startIndex: startIndex, endIndexExclusive: endIndexExclusive)
    requestPreviewUpdate(parameters)
  }

  func updatePlaybackSpeed(_ speed: Double) {
    guard compressedPreview == nil, !isCompressionInProgress else { return }
    guard var parameters = editParameters else { return }
    parameters.playbackSpeed = (speed * 10).rounded() / 10
    requestPreviewUpdate(parameters)
  }

  func updateLoopMode(_ loopMode: GIFLoopMode) {
    guard compressedPreview == nil, !isCompressionInProgress else { return }
    guard var parameters = editParameters else { return }
    parameters.loopMode = loopMode
    requestPreviewUpdate(parameters)
  }

  var isCompressionAvailable: Bool { compressor != nil }

  var isCompressionInProgress: Bool { compressionAction == .compressing }

  var displayedPreviewGIF: EncodedGIF? {
    guard case .previewReady(_, _, let original) = state else { return nil }
    return compressedPreview ?? original
  }

  func selectCompressionDestination(_ destination: GIFCompressionDestination) {
    guard !isCompressionInProgress, compressedPreview == nil else { return }
    compressionSettings.destination = destination
  }

  func selectCompressionScale(_ scale: GIFCompressionScale) {
    guard !isCompressionInProgress, compressedPreview == nil else { return }
    compressionSettings.scale = scale
  }

  func setCompressionQuality(_ percent: Int) {
    guard !isCompressionInProgress, compressedPreview == nil,
      (1...100).contains(percent)
    else { return }
    compressionSettings.qualityPercent = percent
  }

  func startCompression() {
    guard !isPreviewUpdateInProgress, !isPreviewActionInProgress,
      compressionTask == nil, compressedPreview == nil,
      case .previewReady(_, _, let source) = state,
      let compressor
    else { return }
    guard compressionSettings.isValid else {
      compressionAction = .failed
      return
    }
    let request = UUID()
    compressionRequest = request
    compressionAction = .compressing
    originalPreviewExportedBeforeCompression = previewExported
    let settings = compressionSettings
    compressionTask = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.performCompression(
        source: source, settings: settings, compressor: compressor, request: request)
    }
  }

  func cancelCompression() async {
    guard let compressionTask else { return }
    compressionTask.cancel()
    await compressionTask.value
  }

  func backToOriginalPreview() async {
    guard !isCompressionInProgress,
      compressedPreview != nil,
      case .previewReady(let id, _, let original) = state
    else { return }
    do {
      if let compressedPreview {
        try await workspace.removeCompressedPreviewOutput(for: id, at: compressedPreview.url)
      }
      self.compressedPreview = nil
      previewExported = originalPreviewExportedBeforeCompression ?? false
      originalPreviewExportedBeforeCompression = nil
      let snapshot = try await workspace.snapshot(for: id)
      compressionAction = isCompressionAvailable ? .idle : .unavailable
      state = .previewReady(id, snapshot, original)
    } catch {
      compressionAction = .failed
    }
  }

  func copyPreview() async {
    guard !isPreviewUpdateInProgress, !isPreviewActionInProgress,
      let gif = displayedPreviewGIF
    else { return }
    previewAction = .copying
    do {
      try await clipboard.writeGIF(at: gif.url)
      previewExported = true
      previewAction = .copied
    } catch {
      previewAction = .failed
    }
  }

  func savePreview() async {
    guard !isPreviewUpdateInProgress, !isPreviewActionInProgress,
      let gif = displayedPreviewGIF
    else { return }
    previewAction = .saving
    do {
      switch try await fileSaver.saveGIF(at: gif.url) {
      case .saved:
        previewExported = true
        previewAction = .saved
      case .cancelled:
        previewAction = .cancelled
      }
    } catch {
      previewAction = .failed
    }
  }

  func closePreview(discardUnexported: Bool) async -> Bool {
    guard !isPreviewActionInProgress else { return false }
    let id: RecordingSessionID
    switch state {
    case .previewReady(let previewID, _, _), .captured(let previewID, _):
      id = previewID
    default:
      return false
    }
    if discardUnexported { await cancelPreviewReplacement() }
    do {
      if previewExported, case .previewReady = state {
        try await workspace.closePreviewAfterExport(id)
      } else if discardUnexported {
        try await workspace.discard(id)
      } else {
        return false
      }
      sessionID = nil
      previewExported = false
      originalPreviewExportedBeforeCompression = nil
      compressedPreview = nil
      compressionAction = isCompressionAvailable ? .idle : .unavailable
      editParameters = nil
      currentPreviewParameters = nil
      originalSequence = nil
      editFrameCount = 0
      previewAction = .idle
      state = .idle
      return true
    } catch {
      previewAction = .failed
      return false
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
          try await pipeline.consume(prepared.frames) { [weak self] bytes in
            guard let self, self.isCurrent(token) else { return }
            self.recordingWorkspaceBytes = bytes
          }
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
      if let recordingRequestedAt {
        diagnostics.startToRecording = diagnosticsClock.now() - recordingRequestedAt
      }
      state = .recording
    } catch is CancellationError {
      if generation == token {
        if let stream { await stream.stop(reason: .userStopped) }
        await consumerTask?.value
        captureFrameStatistics()
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
    captureFrameStatistics()
    await removeSessionIfPresent()
    clearActiveSession()
    state = .failed(failure)
  }

  private func finish(reason: CaptureTerminationReason) async {
    if let stream { await stream.stop(reason: reason) }
    await consumerTask?.value
    captureFrameStatistics()
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
      if let stopRequestedAt {
        diagnostics.stopToCapturedSession = diagnosticsClock.now() - stopRequestedAt
      }
      state = .captured(sessionID, snapshot)
      previewTask = Task { @MainActor [weak self] in
        await self?.preparePreview(sessionID: sessionID, snapshot: snapshot)
      }
    } catch SessionWorkspaceError.noUsableFrames {
      state = .failed(.noUsableFrames)
    } catch {
      await removeSessionIfPresent()
      state = .failed(.workspaceFailed)
    }
  }

  private func preparePreview(
    sessionID: RecordingSessionID,
    snapshot: RecordingSessionSnapshot
  ) async {
    state = .preparingPreview(sessionID, snapshot)
    previewAction = .idle
    previewExported = false
    originalPreviewExportedBeforeCompression = nil
    compressedPreview = nil
    compressionAction = isCompressionAvailable ? .idle : .unavailable
    var reservation: PreviewOutputReservation?
    do {
      let sequence = try await workspace.pngSequence(for: sessionID)
      originalSequence = sequence
      editFrameCount = sequence.frames.count
      let initialParameters = GIFEditParameters(
        frameRange: GIFFrameRange(startIndex: 0, endIndexExclusive: sequence.frames.count),
        playbackSpeed: 1,
        loopMode: .forever
      )
      editParameters = initialParameters
      currentPreviewParameters = initialParameters
      let edited = try GIFEditModel.apply(initialParameters, to: sequence)
      try Task.checkCancellation()
      let output = try await workspace.reservePreviewOutput(for: sessionID)
      reservation = output
      let encoded = try await gifEncoder.encode(
        edited.sequence, loopMode: edited.loopMode, to: output)
      try validate(encoded, sequence: edited.sequence, loopMode: edited.loopMode, output: output)
      let committed = try await workspace.commitPreviewOutput(for: sessionID, reservation: output)
      if let stopRequestedAt {
        diagnostics.stopToPreviewReady = diagnosticsClock.now() - stopRequestedAt
      }
      state = .previewReady(sessionID, committed, encoded)
    } catch let error as OriginalGIFEncodingError where error == .cancelled {
      if let reservation {
        try? await workspace.abandonPreviewOutput(for: sessionID, reservation: reservation)
      }
      previewAction = .cancelled
      state = .captured(sessionID, snapshot)
    } catch is CancellationError {
      if let reservation {
        try? await workspace.abandonPreviewOutput(for: sessionID, reservation: reservation)
      }
      state = .captured(sessionID, snapshot)
    } catch {
      if let reservation {
        try? await workspace.abandonPreviewOutput(for: sessionID, reservation: reservation)
      }
      previewAction = .failed
      state = .captured(sessionID, snapshot)
    }
    previewTask = nil
  }

  private func performCompression(
    source: EncodedGIF,
    settings: GIFCompressionSettings,
    compressor: any GIFCompressing,
    request: UUID
  ) async {
    guard compressionRequest == request,
      case .previewReady(let previewID, _, let original) = state,
      source == original
    else {
      finishCompression(request, action: .cancelled)
      return
    }

    var reservation: CompressedPreviewOutputReservation?
    var committedURL: URL?
    do {
      let output = try await workspace.reserveCompressedPreviewOutput(
        for: previewID,
        sourceURL: source.url,
        maximumCacheBytes: 0
      )
      reservation = output
      try Task.checkCancellation()
      let compressed = try await compressor.compress(
        source: source, settings: settings, to: output)
      try await Task.detached(priority: .userInitiated) {
        try validateCompressedGIFOutput(
          compressed, source: source, settings: settings, reservation: output)
      }.value
      try Task.checkCancellation()
      _ = try await workspace.commitCompressedPreviewOutput(for: previewID, reservation: output)
      reservation = nil
      committedURL = output.url
      try Task.checkCancellation()
      try await workspace.keepCompressedPreviewOutput(for: previewID, at: output.url)
      try Task.checkCancellation()
      let snapshot = try await workspace.snapshot(for: previewID)
      guard compressionRequest == request, !Task.isCancelled else {
        try? await workspace.removeCompressedPreviewOutput(for: previewID, at: output.url)
        finishCompression(request, action: .cancelled)
        return
      }
      compressedPreview = compressed
      previewExported = false
      state = .previewReady(previewID, snapshot, original)
      compressionAction = .compressed
      compressionTask = nil
      compressionRequest = nil
    } catch {
      if let reservation {
        try? await workspace.abandonCompressedPreviewOutput(
          for: previewID, reservation: reservation)
      }
      if let committedURL {
        try? await workspace.removeCompressedPreviewOutput(for: previewID, at: committedURL)
      }
      finishCompression(request, action: Task.isCancelled ? .cancelled : .failed)
    }
  }

  private func finishCompression(_ request: UUID, action: GIFCompressionAction) {
    guard compressionRequest == request else { return }
    compressionAction = action
    if action == .failed || action == .cancelled {
      originalPreviewExportedBeforeCompression = nil
    }
    compressionTask = nil
    compressionRequest = nil
  }

  private func requestPreviewUpdate(_ parameters: GIFEditParameters) {
    guard !isPreviewActionInProgress,
      case .previewReady(let id, _, _) = state,
      let originalSequence,
      parameters != editParameters,
      parameters.frameRange.startIndex >= 0,
      parameters.frameRange.endIndexExclusive <= originalSequence.frames.count,
      parameters.frameRange.startIndex < parameters.frameRange.endIndexExclusive,
      parameters.playbackSpeed >= 0.5,
      parameters.playbackSpeed <= 2,
      (parameters.playbackSpeed * 10).rounded() == parameters.playbackSpeed * 10
    else { return }
    editParameters = parameters
    previewExported = false
    previewAction = .idle
    isPreviewUpdateInProgress = true
    let request = UUID()
    latestEditRequest = request
    if replacementTask != nil {
      replacementTask?.cancel()
    } else {
      startPreviewReplacement(for: id)
    }
  }

  private func startPreviewReplacement(for id: RecordingSessionID) {
    guard let request = latestEditRequest,
      let parameters = editParameters,
      replacementTask == nil
    else { return }
    replacementTask = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.replacePreview(id: id, parameters: parameters, request: request)
      if self.latestEditRequest != request {
        self.replacementTask = nil
        self.startPreviewReplacement(for: id)
      } else {
        self.replacementTask = nil
      }
    }
  }

  private func replacePreview(
    id: RecordingSessionID,
    parameters: GIFEditParameters,
    request: UUID
  ) async {
    guard latestEditRequest == request, !Task.isCancelled,
      let originalSequence
    else { return }
    var reservation: PreviewOutputReservation?
    do {
      let edited = try GIFEditModel.apply(parameters, to: originalSequence)
      let output = try await workspace.reservePreviewOutput(for: id)
      reservation = output
      try Task.checkCancellation()
      let encoded = try await gifEncoder.encode(
        edited.sequence, loopMode: edited.loopMode, to: output)
      try validate(encoded, sequence: edited.sequence, loopMode: edited.loopMode, output: output)
      try Task.checkCancellation()
      let committed = try await workspace.commitPreviewOutput(for: id, reservation: output)
      guard latestEditRequest == request, !Task.isCancelled else {
        try? await workspace.removeEditedPreviewOutput(for: id, at: output.url)
        return
      }
      state = .previewReady(id, committed, encoded)
      currentPreviewParameters = parameters
      // publishing the validated output must not fail because an obsolete file could not be pruned.
      // the workspace keeps those bytes accounted and removes them when the session closes.
      try? await workspace.keepEditedPreviewOutput(for: id, at: output.url)
      if latestEditRequest == request {
        let currentSnapshot = try await workspace.snapshot(for: id)
        guard latestEditRequest == request else { return }
        state = .previewReady(id, currentSnapshot, encoded)
        isPreviewUpdateInProgress = false
        previewAction = .updated
      }
    } catch is CancellationError {
      if let reservation {
        try? await workspace.abandonPreviewOutput(for: id, reservation: reservation)
      }
      finishPreviewUpdate(request, action: .cancelled)
    } catch let error as OriginalGIFEncodingError where error == .cancelled {
      if let reservation {
        try? await workspace.abandonPreviewOutput(for: id, reservation: reservation)
      }
      finishPreviewUpdate(request, action: .cancelled)
    } catch {
      if let reservation {
        try? await workspace.abandonPreviewOutput(for: id, reservation: reservation)
      }
      finishPreviewUpdate(request, action: .updateFailed)
    }
  }

  private func finishPreviewUpdate(_ request: UUID, action: PreviewAction) {
    guard latestEditRequest == request else { return }
    latestEditRequest = nil
    isPreviewUpdateInProgress = false
    previewAction = action
    editParameters = currentPreviewParameters
    replacementTask = nil
  }

  private func cancelPreviewReplacement() async {
    latestEditRequest = nil
    replacementTask?.cancel()
    await replacementTask?.value
    replacementTask = nil
    isPreviewUpdateInProgress = false
  }

  private func validate(
    _ encoded: EncodedGIF,
    sequence: CapturedPNGSequence,
    loopMode: GIFLoopMode,
    output: PreviewOutputReservation
  ) throws {
    guard encoded.url == output.url,
      encoded.frameCount == sequence.frames.count,
      encoded.width > 0, encoded.height > 0,
      encoded.durationCentiseconds > 0,
      encoded.delaysCentiseconds.count == encoded.frameCount,
      encoded.delaysCentiseconds.allSatisfy({ $0 > 0 }),
      encoded.fileBytes > 0,
      encoded.loopsForever == (loopMode == .forever)
    else { throw OriginalGIFEncodingError.invalidOutput }
    let actual = try GIFMetadataInspector().inspect(encoded.url)
    guard actual == encoded, actual.fileBytes <= output.maximumBytes else {
      throw OriginalGIFEncodingError.invalidOutput
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
    recordingRequestedAt = nil
  }

  private func captureFrameStatistics() {
    guard let stream else { return }
    diagnostics.frameStatistics = stream.frameStatistics
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
