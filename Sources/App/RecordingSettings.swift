import Combine
import SwiftUI

enum RecordingWarningReason: Equatable {
  case duration
  case workspaceSize

  var message: String {
    switch self {
    case .duration: "recording has reached 30 seconds"
    case .workspaceSize: "recording has reached 75% of its temporary space"
    }
  }
}

struct RecordingWarningPolicy {
  static let durationThreshold: TimeInterval = 30
  static let workspaceQuotaFraction = 0.75

  private(set) var hasPresentedWarning = false

  mutating func beginRecording() {
    hasPresentedWarning = false
  }

  mutating func evaluate(
    elapsed: TimeInterval,
    workspaceBytes: Int64,
    workspaceQuotaBytes: Int64
  ) -> RecordingWarningReason? {
    guard !hasPresentedWarning, workspaceQuotaBytes > 0 else { return nil }
    if elapsed >= Self.durationThreshold {
      hasPresentedWarning = true
      return .duration
    }
    let threshold = Int64((Double(workspaceQuotaBytes) * Self.workspaceQuotaFraction).rounded(.up))
    guard workspaceBytes >= threshold else { return nil }
    hasPresentedWarning = true
    return .workspaceSize
  }

  mutating func dismiss() {
    hasPresentedWarning = true
  }
}

@MainActor
final class RecordingSettingsStore: ObservableObject {
  static let cursorKey = "gifferent.recording.showsCursor"

  @Published var showsCursor: Bool {
    didSet { defaults.set(showsCursor, forKey: Self.cursorKey) }
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    showsCursor = defaults.object(forKey: Self.cursorKey) as? Bool ?? true
  }
}

struct RecordingSettingsView: View {
  @ObservedObject var store: RecordingSettingsStore

  var body: some View {
    Form {
      Toggle("include cursor", isOn: $store.showsCursor)
        .accessibilityIdentifier("include-cursor-toggle")
        .accessibilityValue(store.showsCursor ? "included" : "hidden")
    }
    .formStyle(.grouped)
    .frame(minWidth: 320)
    .padding(.vertical, 8)
  }
}
