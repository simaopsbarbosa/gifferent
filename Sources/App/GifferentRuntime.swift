import AppKit
import Combine
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class GifferentRuntime: ObservableObject {
  static let shared = GifferentRuntime()
  private static let recordingWorkspaceQuotaBytes: Int64 = 512 * 1_024 * 1_024

  @Published private(set) var status = "idle"
  @Published private(set) var previewPresentationState: RecordingCoordinatorState = .idle
  @Published private(set) var selectionDescription: String?
  @Published private(set) var recordingWarning: RecordingWarningReason?
  @Published var isPreviewCloseConfirmationPresented = false
  #if DEBUG
    @Published private(set) var recordingFrameFixtureState = "hidden"
  #endif

  let hotkeySettings: HotkeySettingsStore
  let recordingSettings: RecordingSettingsStore

  private let sourceService: CaptureSourceService
  private let selectionCoordinator: CaptureSelectionCoordinator
  private let recordingFrameOverlay = RecordingFrameOverlayController()
  let recordingCoordinator: RecordingCoordinator
  private var permissionWindow: NSWindow?
  private var settingsWindow: NSWindow?
  private var recordingSettingsWindow: NSWindow?
  private var previewWindowController: GIFPreviewWindowController?
  private var lastSelection: CaptureSelection?
  private var recordAfterSelection = false
  private var hasStarted = false
  private var recordingStateObservation: AnyCancellable?
  private var recordingWarningMonitorTask: Task<Void, Never>?
  private var recordingStartedAt: TimeInterval?
  private var recordingWarningPolicy = RecordingWarningPolicy()
  #if DEBUG
    @Published private(set) var recordingCursorFixtureState = "not started"
    private var fixtureRecordingStreamFactory: FixtureRecordingStreamFactory?
  #endif

  private init() {
    let service = CaptureSourceService()
    sourceService = service
    selectionCoordinator = CaptureSelectionCoordinator(sourceService: service)
    hotkeySettings = HotkeySettingsStore(controller: GlobalHotkeyController())
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
        let defaults = UserDefaults(suiteName: "gifferent.ui-testing")
      {
        defaults.removePersistentDomain(forName: "gifferent.ui-testing")
        recordingSettings = RecordingSettingsStore(defaults: defaults)
      } else {
        recordingSettings = RecordingSettingsStore()
      }
    #else
      recordingSettings = RecordingSettingsStore()
    #endif
    let workspace = SessionWorkspaceStore(
      rootDirectory: Self.recordingWorkspaceURL(),
      maximumSessionBytes: Self.recordingWorkspaceQuotaBytes,
      minimumFreeBytes: 64 * 1_024 * 1_024
    )
    let compressor = GifskiCLICompressor.availableInMainBundle()
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
        let fixtureFactory = FixtureRecordingStreamFactory()
        fixtureRecordingStreamFactory = fixtureFactory
        recordingCoordinator = RecordingCoordinator(
          streamFactory: fixtureFactory,
          workspace: workspace,
          compressor: UITestGIFCompressor.configured() ?? compressor,
          clipboard: UITestGIFClipboardWriter(),
          fileSaver: UITestGIFSavePanelSaver()
        )
      } else {
        recordingCoordinator = RecordingCoordinator(
          streamFactory: ScreenCaptureRecordingStreamFactory(sourceService: service),
          workspace: workspace,
          compressor: compressor
        )
      }
    #else
      recordingCoordinator = RecordingCoordinator(
        streamFactory: ScreenCaptureRecordingStreamFactory(sourceService: service),
        workspace: workspace,
        compressor: compressor
      )
    #endif
    recordingStateObservation = recordingCoordinator.$state.sink { [weak self] state in
      self?.updateStatus(for: state)
    }
    #if DEBUG
      fixtureRecordingStreamFactory?.onPrepare = { [weak self] showsCursor in
        self?.recordingCursorFixtureState = showsCursor ? "cursor included" : "cursor hidden"
      }
    #endif
  }

  func start() {
    guard !hasStarted else { return }
    hasStarted = true
    Task { try? await recordingCoordinator.cleanOrphanedSessions() }
    hotkeySettings.onAction = { [weak self] action in
      self?.handle(action)
    }
    hotkeySettings.start()
  }

  func beginSelection() {
    recordAfterSelection = false
    presentSelection()
  }

  private func presentSelection() {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
        presentFixtureSelection()
        return
      }
    #endif

    guard sourceService.authorizationStatus() == .granted else {
      status = "screen recording access needed"
      showPermissionGuide()
      return
    }

    status = "select a capture target"
    selectionCoordinator.present(
      restoring: lastSelection,
      onSelection: { [weak self] selection in
        guard let self else { return }
        self.lastSelection = selection
        self.selectionDescription = Self.describe(selection)
        self.status = "selection ready"
        self.startAfterSelectionIfNeeded(selection)
      },
      onCancel: { [weak self] in
        self?.recordAfterSelection = false
        self?.status = self?.lastSelection == nil ? "idle" : "selection ready"
      },
      onError: { [weak self] error in
        guard let self else { return }
        switch error {
        case .permissionRequired:
          self.status = "screen recording access needed"
          self.showPermissionGuide()
        case .noDisplays:
          self.status = "no display available"
        case .sourceUnavailable:
          self.status = "capture targets unavailable; try again"
        case .screenshotUnavailable:
          self.status = "screen preview unavailable; try again"
        }
      }
    )
  }

  #if DEBUG
    private func presentFixtureSelection() {
      status = "select a capture target"
      selectionCoordinator.presentFixture(
        restoring: lastSelection,
        onSelection: { [weak self] selection in
          guard let self else { return }
          self.lastSelection = selection
          self.selectionDescription = Self.describe(selection)
          self.status = "selection ready"
          self.startAfterSelectionIfNeeded(selection)
        },
        onCancel: { [weak self] in
          self?.recordAfterSelection = false
          self?.status = self?.lastSelection == nil ? "idle" : "selection ready"
        },
        onError: { [weak self] _ in
          self?.status = "selection unavailable"
        }
      )
    }
  #endif

  func showPermissionGuide() {
    if let permissionWindow {
      permissionWindow.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    let window = makeWindow(title: "screen recording access", size: NSSize(width: 420, height: 280))
    window.contentView = NSHostingView(
      rootView: ScreenRecordingPermissionGuide(onGranted: { [weak self] in
        self?.permissionWindow?.close()
        self?.permissionWindow = nil
        self?.presentSelection()
      })
    )
    permissionWindow = window
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func showHotkeySettings() {
    if let settingsWindow {
      settingsWindow.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    let window = makeWindow(title: "shortcuts", size: NSSize(width: 460, height: 220))
    window.contentView = NSHostingView(rootView: HotkeySettingsView(store: hotkeySettings))
    settingsWindow = window
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func showRecordingSettings() {
    if let recordingSettingsWindow {
      recordingSettingsWindow.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    let window = makeWindow(title: "recording settings", size: NSSize(width: 360, height: 150))
    window.contentView = NSHostingView(rootView: RecordingSettingsView(store: recordingSettings))
    recordingSettingsWindow = window
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func dismissRecordingWarning() {
    recordingWarningPolicy.dismiss()
    recordingWarning = nil
  }

  #if DEBUG
    func simulateWindowLossFixture() {
      guard case .recording = recordingCoordinator.state else { return }
      fixtureRecordingStreamFactory?.reportWindowLoss()
    }

    func showRecordingWarningFixture() {
      guard recordingStartedAt != nil else { return }
      recordingStartedAt =
        ProcessInfo.processInfo.systemUptime - RecordingWarningPolicy.durationThreshold
      refreshRecordingWarning()
    }

    func showWorkspaceWarningFixture() {
      guard recordingStartedAt != nil else { return }
      recordingCoordinator.setRecordingWorkspaceBytesFixture(
        Int64(
          (Double(Self.recordingWorkspaceQuotaBytes)
            * RecordingWarningPolicy.workspaceQuotaFraction).rounded(.up))
      )
      refreshRecordingWarning()
    }
  #endif

  private func handle(_ action: GlobalHotkeyAction) {
    switch action {
    case .capture:
      beginSelection()
    case .record:
      toggleRecording()
    }
  }

  func toggleRecording() {
    switch recordingCoordinator.state {
    case .starting, .recording:
      Task { await recordingCoordinator.stop() }
    case .stopping:
      break
    case .captured:
      status = "discard captured frames before recording again"
    case .preparingPreview, .previewReady:
      break
    case .idle, .failed:
      guard let lastSelection else {
        recordAfterSelection = true
        presentSelection()
        return
      }
      startRecording(for: lastSelection)
    }
  }

  func discardCapturedFrames() {
    Task { await recordingCoordinator.discardCapturedSession() }
  }

  func copyPreview() {
    Task { await recordingCoordinator.copyPreview() }
  }

  func savePreview() {
    Task { await recordingCoordinator.savePreview() }
  }

  func requestPreviewClose() {
    guard !recordingCoordinator.isPreviewActionInProgress else {
      status = "wait for compression or export to finish before closing the preview"
      return
    }
    Task {
      if await recordingCoordinator.closePreview(discardUnexported: false) {
        previewWindowController?.closeAfterCleanup()
      } else {
        switch recordingCoordinator.state {
        case .captured, .preparingPreview, .previewReady:
          isPreviewCloseConfirmationPresented = true
        default:
          status = "could not close preview; temporary files remain"
        }
      }
    }
  }

  func confirmPreviewDiscard() {
    guard !recordingCoordinator.isPreviewActionInProgress else {
      status = "wait for compression or export to finish before discarding the preview"
      return
    }
    isPreviewCloseConfirmationPresented = false
    Task {
      let discarded: Bool
      switch recordingCoordinator.state {
      case .captured, .previewReady:
        discarded = await recordingCoordinator.closePreview(discardUnexported: true)
      case .preparingPreview:
        await recordingCoordinator.discardCapturedSession()
        discarded = recordingCoordinator.state == .idle
      default:
        discarded = false
      }
      if discarded {
        previewWindowController?.closeAfterCleanup()
      } else {
        status = "could not discard preview; temporary files remain"
      }
    }
  }

  func retryPreview() {
    recordingCoordinator.retryPreviewEncoding()
  }

  func cancelPreviewDiscard() {
    isPreviewCloseConfirmationPresented = false
  }

  func requestDiscardPreview() {
    guard !recordingCoordinator.isPreviewActionInProgress else {
      status = "wait for compression or export to finish before discarding the preview"
      return
    }
    isPreviewCloseConfirmationPresented = true
  }

  func previewWindowDidClose(_ controller: GIFPreviewWindowController) {
    guard previewWindowController === controller else { return }
    previewWindowController = nil
  }

  var recordingActionTitle: String {
    switch recordingCoordinator.state {
    case .starting, .recording, .stopping: "stop recording"
    case .captured, .preparingPreview: "preparing preview"
    case .previewReady: "preview ready"
    case .idle, .failed: "start recording"
    }
  }

  var recordingActionIsDisabled: Bool {
    switch recordingCoordinator.state {
    case .stopping, .captured, .preparingPreview, .previewReady: true
    default: false
    }
  }

  func performRecordingAction() {
    switch recordingCoordinator.state {
    case .captured, .preparingPreview, .previewReady:
      return
    default:
      toggleRecording()
    }
  }

  #if DEBUG
    func showRecordingFrameFixture() {
      recordingFrameOverlay.showFixture(
        frame: CGRect(x: 110, y: 110, width: 220, height: 130))
      recordingFrameFixtureState = recordingFrameOverlay.fixtureStateDescription
    }

    func moveRecordingFrameFixture() {
      recordingFrameOverlay.moveFixture(
        to: CGRect(x: 180, y: 160, width: 260, height: 150))
      recordingFrameFixtureState = recordingFrameOverlay.fixtureStateDescription
    }

    func hideRecordingFrameFixture() {
      recordingFrameOverlay.hide()
      recordingFrameFixtureState = recordingFrameOverlay.fixtureStateDescription
    }
  #endif

  private func startAfterSelectionIfNeeded(_ selection: CaptureSelection) {
    guard recordAfterSelection else { return }
    recordAfterSelection = false
    startRecording(for: selection)
  }

  private func startRecording(for selection: CaptureSelection) {
    #if DEBUG
      let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    #else
      let isUITesting = false
    #endif
    guard isUITesting || sourceService.authorizationStatus() == .granted else {
      recordAfterSelection = true
      status = "screen recording access needed"
      showPermissionGuide()
      return
    }
    let target = RecordingTarget(selection: selection)
    Task {
      await recordingCoordinator.start(target: target, showsCursor: recordingSettings.showsCursor)
    }
  }

  private func updateStatus(for state: RecordingCoordinatorState) {
    previewPresentationState = state
    switch state {
    case .idle:
      endRecordingWarningMonitoring()
      recordingFrameOverlay.hide()
      status = lastSelection == nil ? "idle" : "selection ready"
    case .starting:
      endRecordingWarningMonitoring()
      status = "starting recording"
    case .recording:
      status = "recording"
      beginRecordingWarningMonitoringIfNeeded()
      showRecordingFrame(for: lastSelection)
      #if DEBUG
        recordingFrameFixtureState = recordingFrameOverlay.fixtureStateDescription
      #endif
    case .stopping:
      endRecordingWarningMonitoring()
      // stopCapture drains queued samples. remove the indicator before that
      // drain so a late frame cannot contain the overlay.
      recordingFrameOverlay.hide()
      #if DEBUG
        recordingFrameFixtureState = recordingFrameOverlay.fixtureStateDescription
      #endif
      status = "stopping recording"
    case .captured(_, let snapshot):
      endRecordingWarningMonitoring()
      recordingFrameOverlay.hide()
      switch snapshot.stopReason {
      case .windowUnavailable:
        status = "window ended; preparing partial preview"
      case .displayUnavailable:
        status = "display disconnected; preparing partial preview"
      case .user, .none:
        status = "preparing preview"
      }
    case .preparingPreview:
      endRecordingWarningMonitoring()
      recordingFrameOverlay.hide()
      status = "preparing preview"
      showPreviewWindow()
    case .previewReady:
      endRecordingWarningMonitoring()
      recordingFrameOverlay.hide()
      status = "preview ready"
      showPreviewWindow()
    case .failed(let failure):
      endRecordingWarningMonitoring()
      recordingFrameOverlay.hide()
      switch failure {
      case .permissionRequired:
        status = "screen recording access needed"
      case .permissionLost:
        status = "screen recording access lost"
      case .captureStartFailed:
        status = "could not start recording; try again"
      case .frameEncodingFailed:
        status = "could not process captured frames"
      case .frameStorageFailed, .workspaceFailed:
        status = "could not store recording data; check available storage"
      case .streamFailed:
        status = "recording stopped unexpectedly"
      case .noUsableFrames:
        status = "no frames captured; try again"
      case .cancelled:
        status = "recording cancelled"
      case .gifEncodingFailed:
        status = "could not create a valid gif; captured frames were retained"
      }
    }
  }

  private func beginRecordingWarningMonitoringIfNeeded() {
    guard recordingWarningMonitorTask == nil else { return }
    recordingWarningPolicy.beginRecording()
    recordingWarning = nil
    recordingStartedAt = ProcessInfo.processInfo.systemUptime
    recordingWarningMonitorTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        self.refreshRecordingWarning()
        if self.recordingWarningPolicy.hasPresentedWarning { return }
        try? await Task.sleep(for: .milliseconds(250))
      }
    }
  }

  private func refreshRecordingWarning() {
    guard recordingWarning == nil, let recordingStartedAt else { return }
    recordingWarning = recordingWarningPolicy.evaluate(
      elapsed: ProcessInfo.processInfo.systemUptime - recordingStartedAt,
      workspaceBytes: recordingCoordinator.recordingWorkspaceBytes,
      workspaceQuotaBytes: Self.recordingWorkspaceQuotaBytes
    )
  }

  private func endRecordingWarningMonitoring() {
    recordingWarningMonitorTask?.cancel()
    recordingWarningMonitorTask = nil
    recordingStartedAt = nil
    recordingWarning = nil
  }

  private func showPreviewWindow() {
    if let previewWindowController {
      previewWindowController.showWindow()
      return
    }
    let controller = GIFPreviewWindowController(runtime: self, coordinator: recordingCoordinator)
    previewWindowController = controller
    controller.showWindow()
  }

  private func showRecordingFrame(for selection: CaptureSelection?) {
    guard let selection else { return }
    switch selection {
    case .display:
      recordingFrameOverlay.hide()
    case .region(let geometry):
      recordingFrameOverlay.show(region: geometry)
    case .window(let id):
      recordingFrameOverlay.show(windowID: id)
    }
  }

  private static func describe(_ selection: CaptureSelection) -> String {
    switch selection {
    case .display:
      "display selected"
    case .window:
      "window selected"
    case .region:
      "region selected"
    }
  }

  private func makeWindow(title: String, size: NSSize) -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = title
    window.center()
    window.isReleasedWhenClosed = false
    return window
  }

  private static func recordingWorkspaceURL() -> URL {
    let cacheRoot =
      FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return cacheRoot.appendingPathComponent("gifferent/recording-sessions", isDirectory: true)
  }
}

@MainActor
struct NSPasteboardGIFWriter: GIFClipboardWriting {
  func writeGIF(at url: URL) async throws {
    let data = try await Task.detached(priority: .userInitiated) {
      try Data(contentsOf: url, options: .mappedIfSafe)
    }.value
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    guard pasteboard.setData(data, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))
    else { throw NSError(domain: "gifferent.clipboard", code: 1) }
  }
}

@MainActor
struct SavePanelGIFSaver: GIFSaving {
  func saveGIF(at url: URL) async throws -> PreviewSaveResult {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.gif]
    panel.canCreateDirectories = true
    panel.nameFieldStringValue = "gifferent.gif"
    panel.title = "save gif"
    panel.prompt = "save"
    let response = await withCheckedContinuation { continuation in
      panel.begin { continuation.resume(returning: $0) }
    }
    guard response == .OK, let destination = panel.url else { return .cancelled }
    try await Task.detached(priority: .utility) {
      let fileManager = FileManager.default
      let staged = destination.deletingLastPathComponent()
        .appendingPathComponent(".gifferent-\(UUID().uuidString).gif")
      defer { try? fileManager.removeItem(at: staged) }
      try fileManager.copyItem(at: url, to: staged)
      if fileManager.fileExists(atPath: destination.path) {
        _ = try fileManager.replaceItemAt(destination, withItemAt: staged)
      } else {
        try fileManager.moveItem(at: staged, to: destination)
      }
    }.value
    return .saved
  }
}

#if DEBUG
  private func uiTestExportDirectory() -> URL {
    if let path = ProcessInfo.processInfo.environment["GIFFERENT_UI_TEST_EXPORT_DIRECTORY"] {
      return URL(fileURLWithPath: path, isDirectory: true)
    }
    return FileManager.default.temporaryDirectory
  }

  @MainActor
  private struct UITestGIFClipboardWriter: GIFClipboardWriting {
    func writeGIF(at url: URL) async throws {
      let destination = uiTestExportDirectory()
        .appendingPathComponent("gifferent-preview-ui-copy.gif")
      try? FileManager.default.removeItem(at: destination)
      try FileManager.default.copyItem(at: url, to: destination)
    }
  }

  private struct UITestGIFCompressor: GIFCompressing {
    let outcome: String

    static func configured() -> Self? {
      let prefix = "--ui-testing-compression="
      guard
        let argument = ProcessInfo.processInfo.arguments.first(where: {
          $0.hasPrefix(prefix)
        })
      else { return nil }
      return Self(outcome: String(argument.dropFirst(prefix.count)))
    }

    func compress(
      source: EncodedGIF,
      settings: GIFCompressionSettings,
      to reservation: CompressedPreviewOutputReservation
    ) async throws -> EncodedGIF {
      if outcome == "failure" { throw GifskiCompressionError.invalidOutput }
      if outcome == "cancellable" {
        try await Task.sleep(for: .seconds(60))
        throw GifskiCompressionError.invalidOutput
      }
      return try await Task.detached(priority: .utility) {
        let sample = try GIFFrameSampler.sample(
          delaysCentiseconds: source.delaysCentiseconds, frameRate: settings.frameRate)
        guard let input = CGImageSourceCreateWithURL(source.url as CFURL, nil),
          let destination = CGImageDestinationCreateWithURL(
            reservation.url as CFURL, UTType.gif.identifier as CFString,
            sample.sourceIndices.count, nil)
        else { throw GifskiCompressionError.invalidOutput }
        if source.loopsForever {
          CGImageDestinationSetProperties(
            destination,
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        }
        let width = max(1, settings.scale.expectedDimension(source.width))
        let height = max(1, settings.scale.expectedDimension(source.height))
        for (index, sourceIndex) in sample.sourceIndices.enumerated() {
          guard let image = CGImageSourceCreateImageAtIndex(input, sourceIndex, nil),
            let context = CGContext(
              data: nil, width: width, height: height, bitsPerComponent: 8,
              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
          else { throw GifskiCompressionError.invalidOutput }
          context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
          guard let scaled = context.makeImage() else {
            throw GifskiCompressionError.invalidOutput
          }
          let delay = Double(sample.expectedDelaysCentiseconds[index]) / 100
          CGImageDestinationAddImage(
            destination, scaled,
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
          throw GifskiCompressionError.invalidOutput
        }
        if outcome == "miss" {
          let handle = try FileHandle(forWritingTo: reservation.url)
          defer { try? handle.close() }
          let end = try handle.seekToEnd()
          try handle.truncate(atOffset: end - 1)
          try handle.seek(toOffset: end - 1)
          try handle.write(contentsOf: Data([0x21, 0xfe]))
          var block = Data([255])
          block.append(Data(repeating: 0, count: 255))
          var batch = Data()
          for _ in 0..<256 { batch.append(block) }
          var bytes = Int64(end + 1)
          while bytes <= settings.destination.targetBytes {
            try handle.write(contentsOf: batch)
            bytes += Int64(batch.count)
          }
          try handle.write(contentsOf: Data([0, 0x3b]))
        }
        return try GIFMetadataInspector().inspect(reservation.url)
      }.value
    }
  }

  @MainActor
  private struct UITestGIFSavePanelSaver: GIFSaving {
    func saveGIF(at url: URL) async throws -> PreviewSaveResult {
      let destination = uiTestExportDirectory()
        .appendingPathComponent("gifferent-preview-ui-save.gif")
      try? FileManager.default.removeItem(at: destination)
      try FileManager.default.copyItem(at: url, to: destination)
      return .saved
    }
  }

  @MainActor
  private final class FixtureRecordingStreamFactory: RecordingStreamPreparing {
    var onPrepare: ((Bool) -> Void)?
    private var windowTermination: (@MainActor (CaptureTerminationReason) -> Void)?

    func prepare(
      target: RecordingTarget,
      showsCursor: Bool,
      onTermination: @escaping @MainActor (CaptureTerminationReason) -> Void
    ) async throws -> any RecordingCaptureSession {
      onPrepare?(showsCursor)
      if case .window = target {
        windowTermination = onTermination
      } else {
        windowTermination = nil
      }
      return FixtureRecordingCaptureSession()
    }

    func reportWindowLoss() {
      let callback = windowTermination
      windowTermination = nil
      callback?(.windowUnavailable)
    }
  }

  @MainActor
  private final class FixtureRecordingCaptureSession: RecordingCaptureSession {
    private let transport = RecordingFrameTransport()
    var frames: AsyncStream<RecordingFrame> { transport.frames }

    func start() async throws {
      let pixels = Data(repeating: 0x7f, count: 16 * 16 * 4)
      for frameIndex in 0..<3 {
        transport.offer(
          RecordingFrame(
            timestampNanoseconds: Int64(frameIndex + 1) * 41_666_667,
            width: 16,
            height: 16,
            bytesPerRow: 16 * 4,
            bgra: pixels
          ))
      }
    }

    func stop(reason _: CaptureTerminationReason) async {
      transport.finish()
    }
  }
#endif
