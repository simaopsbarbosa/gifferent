import AppKit
import SwiftUI

@main
struct GifferentApp: App {
  @NSApplicationDelegateAdaptor(GifferentAppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra("gifferent") {
      GifferentMenuContent(runtime: .shared)
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

private struct GifferentMenuContent: View {
  @ObservedObject var runtime: GifferentRuntime

  var body: some View {
    Text(runtime.status)
      .accessibilityIdentifier("app-status")
      .accessibilityLabel(runtime.status)

    if let selectionDescription = runtime.selectionDescription {
      Text(selectionDescription)
        .accessibilityIdentifier("selection-status")
        .accessibilityLabel(selectionDescription)
    }

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

    Divider()

    Button("quit") {
      NSApplication.shared.terminate(nil)
    }
    .accessibilityIdentifier("quit-button")
  }
}
