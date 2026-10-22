import AppKit
import SwiftUI

@main
struct GifferentApp: App {
  var body: some Scene {
    MenuBarExtra("gifferent") {
      Text("idle")
        .accessibilityIdentifier("app-status")

      Divider()

      Button("quit") {
        NSApplication.shared.terminate(nil)
      }
      .accessibilityIdentifier("quit-button")
    }
  }
}
