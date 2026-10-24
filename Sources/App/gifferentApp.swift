import AppKit
import SwiftUI

@main
struct GifferentApp: App {
  @NSApplicationDelegateAdaptor(GifferentAppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra {
      GifferentMenuContent(runtime: .shared)
    } label: {
      Image("MenuBarMark")
        .resizable()
        .interpolation(.high)
        .renderingMode(.original)
        .frame(width: 16, height: 16)
        .accessibilityLabel("gifferent")
        .accessibilityIdentifier("menu-bar-mark")
    }
  }
}

@MainActor
private final class GifferentAppDelegate: NSObject, NSApplicationDelegate {
  #if DEBUG
    private var testingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
      if !ProcessInfo.processInfo.arguments.contains("--ui-testing") {
        GifferentRuntime.shared.start()
        return
      }

      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
      )
      window.title = "gifferent test menu"
      window.contentView = NSHostingView(rootView: GifferentMenuContent(runtime: .shared).padding())
      window.center()
      window.makeKeyAndOrderFront(nil)
      testingWindow = window
    }
  #endif

  #if !DEBUG
    func applicationDidFinishLaunching(_ notification: Notification) {
      GifferentRuntime.shared.start()
    }
  #endif
}

@MainActor
private struct GifferentMenuContent: View {
  @ObservedObject var runtime: GifferentRuntime
  @State private var displayedStatus: String

  init(runtime: GifferentRuntime) {
    self.runtime = runtime
    _displayedStatus = State(initialValue: runtime.status)
  }

  var body: some View {
    Text(displayedStatus)
      .accessibilityIdentifier("app-status")
      .accessibilityLabel("status")
      .accessibilityValue(displayedStatus)
      .onReceive(runtime.$status) { status in
        displayedStatus = status
      }

    if let warning = runtime.recordingWarning {
      Text(warning.message)
        .accessibilityIdentifier("recording-warning")
        .accessibilityLabel(warning.message)
        .accessibilityValue(warning.message)
      Button("dismiss") { runtime.dismissRecordingWarning() }
        .accessibilityIdentifier("dismiss-recording-warning-button")
    }

    if let selectionDescription = runtime.selectionDescription {
      Text(selectionDescription)
        .accessibilityIdentifier("selection-status")
        .accessibilityLabel("selection status")
        .accessibilityValue(selectionDescription)
    }

    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
        Text(runtime.recordingFrameFixtureState)
          .accessibilityIdentifier("recording-frame-fixture-state")
          .accessibilityLabel("recording frame fixture state")
          .accessibilityValue(runtime.recordingFrameFixtureState)
        Text(runtime.recordingCursorFixtureState)
          .accessibilityIdentifier("recording-cursor-fixture-state")
          .accessibilityLabel("recording cursor fixture state")
          .accessibilityValue(runtime.recordingCursorFixtureState)
        Button("show recording warning fixture") { runtime.showRecordingWarningFixture() }
          .accessibilityIdentifier("show-recording-warning-button")
        Button("show workspace warning fixture") { runtime.showWorkspaceWarningFixture() }
          .accessibilityIdentifier("show-workspace-warning-button")
        Button("lose selected window fixture") { runtime.simulateWindowLossFixture() }
          .accessibilityIdentifier("lose-selected-window-button")
      }
    #endif

    Divider()

    Button("select capture…") {
      runtime.beginSelection()
    }
    .accessibilityIdentifier("select-capture-button")

    Button(runtime.recordingActionTitle) {
      runtime.performRecordingAction()
    }
    .disabled(runtime.recordingActionIsDisabled)
    .accessibilityIdentifier("recording-action-button")

    Button("shortcuts…") {
      runtime.showHotkeySettings()
    }
    .accessibilityIdentifier("shortcuts-button")

    Button("recording settings…") {
      runtime.showRecordingSettings()
    }
    .accessibilityIdentifier("recording-settings-button")

    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
        Button("show recording frame fixture") { runtime.showRecordingFrameFixture() }
          .accessibilityIdentifier("show-recording-frame-button")
        Button("move recording frame fixture") { runtime.moveRecordingFrameFixture() }
          .accessibilityIdentifier("move-recording-frame-button")
        Button("hide recording frame fixture") { runtime.hideRecordingFrameFixture() }
          .accessibilityIdentifier("hide-recording-frame-button")
      }
    #endif

    Divider()

    Button("quit") {
      NSApplication.shared.terminate(nil)
    }
    .accessibilityIdentifier("quit-button")
  }
}

@MainActor
final class GIFPreviewWindowController: NSObject, NSWindowDelegate {
  weak var runtime: GifferentRuntime?
  let window: NSWindow
  private var mayClose = false

  init(runtime: GifferentRuntime, coordinator: RecordingCoordinator) {
    self.runtime = runtime
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    super.init()
    window.title = "gif preview"
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.contentView = NSHostingView(
      rootView: GIFPreviewView(runtime: runtime, coordinator: coordinator)
    )
  }

  func showWindow() {
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  func closeAfterCleanup() {
    mayClose = true
    window.close()
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if mayClose { return true }
    runtime?.requestPreviewClose()
    return false
  }

  func windowWillClose(_ notification: Notification) {
    runtime?.previewWindowDidClose(self)
  }
}

@MainActor
private struct GIFPreviewView: View {
  @ObservedObject var runtime: GifferentRuntime
  @ObservedObject var coordinator: RecordingCoordinator

  var body: some View {
    Group {
      switch coordinator.state {
      case .preparingPreview:
        VStack(spacing: 14) {
          ProgressView()
            .accessibilityLabel("preparing gif preview")
          Text("preparing preview")
            .accessibilityIdentifier("preview-status")
            .accessibilityValue("preparing preview")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .captured:
        VStack(spacing: 14) {
          Text("could not create a valid gif")
            .accessibilityIdentifier("preview-status")
            .accessibilityValue("could not create a valid gif")
          Text("your captured frames are still available")
          HStack {
            Button("try again") { runtime.retryPreview() }
              .accessibilityIdentifier("retry-preview-button")
            Button("discard") { runtime.requestDiscardPreview() }
              .disabled(
                coordinator.previewAction == .copying || coordinator.previewAction == .saving
              )
              .accessibilityIdentifier("discard-preview-button")
            Button("close") { runtime.requestPreviewClose() }
              .accessibilityIdentifier("close-preview-button")
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .previewReady(_, let snapshot, let gif):
        GIFPreviewReadyView(
          runtime: runtime,
          coordinator: coordinator,
          snapshot: snapshot,
          gif: gif
        )
        .padding(18)
      case .failed(let failure):
        VStack(spacing: 12) {
          Text(failureMessage(failure))
            .accessibilityIdentifier("preview-status")
            .accessibilityValue(failureMessage(failure))
          Button("close") { runtime.requestPreviewClose() }
            .accessibilityIdentifier("close-preview-button")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      default:
        Text("preparing preview")
          .accessibilityIdentifier("preview-status")
          .accessibilityValue("preparing preview")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .frame(minWidth: 440, minHeight: 360)
    .confirmationDialog(
      "discard this preview?",
      isPresented: $runtime.isPreviewCloseConfirmationPresented,
      titleVisibility: .visible
    ) {
      Button("discard", role: .destructive) { runtime.confirmPreviewDiscard() }
        .accessibilityIdentifier("confirm-preview-discard-button")
      Button("keep preview", role: .cancel) { runtime.cancelPreviewDiscard() }
        .accessibilityIdentifier("keep-preview-button")
    } message: {
      Text("the temporary gif will be deleted.")
    }
  }

  private func failureMessage(_ failure: RecordingCoordinatorFailure) -> String {
    switch failure {
    case .gifEncodingFailed: "could not create a valid gif; captured frames were retained"
    case .workspaceFailed, .frameStorageFailed:
      "could not store recording data; check available storage"
    default: "recording could not be completed"
    }
  }
}
