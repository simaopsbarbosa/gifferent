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
  private var permissionWindow: NSWindow?
  private var settingsWindow: NSWindow?
  private var lastSelection: CaptureSelection?
  private var hasStarted = false

  private init() {
    let service = CaptureSourceService()
    sourceService = service
    selectionCoordinator = CaptureSelectionCoordinator(sourceService: service)
    hotkeySettings = HotkeySettingsStore(controller: GlobalHotkeyController())
  }

  func start() {
    guard !hasStarted else { return }
    hasStarted = true
    hotkeySettings.onAction = { [weak self] action in
      self?.handle(action)
    }
    hotkeySettings.start()
  }

  func beginSelection() {
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
      },
      onCancel: { [weak self] in
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
        },
        onCancel: { [weak self] in
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
        self?.beginSelection()
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
      if lastSelection == nil {
        beginSelection()
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
}
