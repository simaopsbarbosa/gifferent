import AppKit
import Combine
import SwiftUI

@MainActor
final class GifferentRuntime: ObservableObject {
  static let shared = GifferentRuntime()

  @Published private(set) var status = "idle"
  @Published private(set) var selectionDescription: String?

  let hotkeySettings: HotkeySettingsStore

  private let sourceService: CaptureSourceService
  private let selectionCoordinator: CaptureSelectionCoordinator
  let recordingCoordinator: RecordingCoordinator
  private var permissionWindow: NSWindow?
  private var settingsWindow: NSWindow?
  private var lastSelection: CaptureSelection?
  private var recordAfterSelection = false
  private var hasStarted = false
  private var recordingStateObservation: AnyCancellable?

  private init() {
    let service = CaptureSourceService()
    sourceService = service
    selectionCoordinator = CaptureSelectionCoordinator(sourceService: service)
    hotkeySettings = HotkeySettingsStore(controller: GlobalHotkeyController())
    let workspace = SessionWorkspaceStore(
      rootDirectory: Self.recordingWorkspaceURL(),
      maximumSessionBytes: 512 * 1_024 * 1_024,
      minimumFreeBytes: 64 * 1_024 * 1_024
    )
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
        recordingCoordinator = RecordingCoordinator(
          streamFactory: FixtureRecordingStreamFactory(), workspace: workspace)
      } else {
        recordingCoordinator = RecordingCoordinator(
          streamFactory: ScreenCaptureRecordingStreamFactory(sourceService: service),
          workspace: workspace
        )
      }
    #else
      recordingCoordinator = RecordingCoordinator(
        streamFactory: ScreenCaptureRecordingStreamFactory(sourceService: service),
        workspace: workspace
      )
    #endif
    recordingStateObservation = recordingCoordinator.$state.sink { [weak self] state in
      self?.updateStatus(for: state)
    }
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

  var recordingActionTitle: String {
    switch recordingCoordinator.state {
    case .starting, .recording, .stopping: "stop recording"
    case .captured: "discard captured frames"
    case .idle, .failed: "start recording"
    }
  }

  var recordingActionIsDisabled: Bool {
    if case .stopping = recordingCoordinator.state { return true }
    return false
  }

  func performRecordingAction() {
    if case .captured = recordingCoordinator.state {
      discardCapturedFrames()
    } else {
      toggleRecording()
    }
  }

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
    Task { await recordingCoordinator.start(target: target, showsCursor: true) }
  }

  private func updateStatus(for state: RecordingCoordinatorState) {
    switch state {
    case .idle:
      status = lastSelection == nil ? "idle" : "selection ready"
    case .starting:
      status = "starting recording"
    case .recording:
      status = "recording"
    case .stopping:
      status = "stopping recording"
    case .captured(_, let snapshot):
      switch snapshot.stopReason {
      case .windowUnavailable:
        status = "window ended; partial frames ready to discard"
      case .displayUnavailable:
        status = "display disconnected; partial frames ready to discard"
      case .user, .none:
        status = "frames captured; GIF preview is not available yet"
      }
    case .failed(let failure):
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
      }
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

#if DEBUG
  @MainActor
  private struct FixtureRecordingStreamFactory: RecordingStreamPreparing {
    func prepare(
      target _: RecordingTarget,
      showsCursor _: Bool,
      onTermination _: @escaping @MainActor (CaptureTerminationReason) -> Void
    ) async throws -> any RecordingCaptureSession {
      FixtureRecordingCaptureSession()
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
