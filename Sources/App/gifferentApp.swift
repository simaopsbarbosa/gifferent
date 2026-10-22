import AppKit
import SwiftUI

@main
struct GifferentApp: App {
  @NSApplicationDelegateAdaptor(GifferentAppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra("gifferent") {
      GifferentMenuContent()
    }
  }
}

@MainActor
private final class GifferentAppDelegate: NSObject, NSApplicationDelegate {
  #if DEBUG
    private var testingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
      guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }

      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
      )
      window.title = "gifferent test menu"
      window.contentView = NSHostingView(rootView: GifferentMenuContent().padding())
      window.center()
      window.makeKeyAndOrderFront(nil)
      testingWindow = window
    }
  #endif
}

private struct GifferentMenuContent: View {
  var body: some View {
    Text("idle")
      .accessibilityIdentifier("app-status")

    Divider()

    Button("quit") {
      NSApplication.shared.terminate(nil)
    }
    .accessibilityIdentifier("quit-button")
  }
}
