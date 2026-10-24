import AppKit
import SwiftUI

enum ScreenRecordingPermissionGuideState: Equatable {
  case needsPermission
  case granted
  case settingsUnavailable
  case restartRequired
}

@MainActor
final class ScreenRecordingPermissionGuideModel: ObservableObject {
  @Published private(set) var state: ScreenRecordingPermissionGuideState
  @Published private(set) var hasRequestedPermission = false

  private let permission: any ScreenRecordingPermissionProviding
  private let openSystemSettings: @MainActor () -> Bool
  private let onGranted: @MainActor () -> Void
  private var hasReportedGrant = false
  private var hasOpenedSettings = false

  init(
    permission: (any ScreenRecordingPermissionProviding)? = nil,
    openSystemSettings: @escaping @MainActor () -> Bool = {
      NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    },
    onGranted: @escaping @MainActor () -> Void = {}
  ) {
    self.permission = permission ?? SystemScreenRecordingPermission()
    self.openSystemSettings = openSystemSettings
    self.onGranted = onGranted
    state = self.permission.preflight() == .granted ? .granted : .needsPermission
  }

  func refresh() {
    update(
      for: permission.preflight(),
      afterSettingsChange: hasOpenedSettings || hasRequestedPermission
    )
  }

  func requestPermission() {
    hasRequestedPermission = true
    update(for: permission.request(), afterSettingsChange: true)
  }

  func openSettings() {
    guard openSystemSettings() else {
      state = .settingsUnavailable
      return
    }
    hasOpenedSettings = true
    if state == .settingsUnavailable {
      state = .needsPermission
    }
  }

  private func update(
    for authorization: ScreenRecordingAuthorization,
    afterSettingsChange: Bool = false
  ) {
    switch authorization {
    case .granted:
      state = .granted
      if !hasReportedGrant {
        hasReportedGrant = true
        onGranted()
      }
    case .needsPermission:
      state = afterSettingsChange ? .restartRequired : .needsPermission
      hasReportedGrant = false
    }
  }
}

struct ScreenRecordingPermissionGuide: View {
  @StateObject private var model: ScreenRecordingPermissionGuideModel
  @Environment(\.scenePhase) private var scenePhase

  init(
    permission: (any ScreenRecordingPermissionProviding)? = nil,
    openSystemSettings: @escaping @MainActor () -> Bool = {
      NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    },
    onGranted: @escaping @MainActor () -> Void = {}
  ) {
    _model = StateObject(
      wrappedValue: ScreenRecordingPermissionGuideModel(
        permission: permission,
        openSystemSettings: openSystemSettings,
        onGranted: onGranted
      )
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("allow screen recording to continue")
        .font(.headline)

      if model.state == .granted {
        Text("screen recording is ready")
          .accessibilityIdentifier("screen-recording-permission-status")
      } else {
        Text("1. allow gifferent to record your screen.")
        Text("2. return here and check access again.")

        if model.state == .restartRequired {
          Text(
            "macos still reports access as off. if you just enabled it, quit and reopen gifferent, then check again."
          )
          .font(.caption)
          .accessibilityIdentifier("screen-recording-restart-required")
        }

        if model.hasRequestedPermission {
          Text(
            "if access was denied, turn on gifferent in system settings. if access still appears off, quit and reopen gifferent."
          )
          .font(.caption)
        }

        if model.state == .settingsUnavailable {
          Text("couldn't open system settings. open privacy & security, then screen recording.")
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("screen-recording-settings-error")
        }

        VStack(alignment: .leading, spacing: 8) {
          Button("allow screen recording") {
            model.requestPermission()
          }
          .accessibilityIdentifier("screen-recording-request")

          Button("open system settings") {
            model.openSettings()
          }
          .accessibilityIdentifier("screen-recording-settings")

          Button("check again") {
            model.refresh()
          }
          .accessibilityIdentifier("screen-recording-recheck")
        }
      }
    }
    .padding()
    .onAppear {
      model.refresh()
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        model.refresh()
      }
    }
  }
}
