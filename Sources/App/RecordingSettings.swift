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
        .accessibilityLabel("include cursor, \(store.showsCursor ? "included" : "hidden")")
    }
    .formStyle(.grouped)
    .frame(minWidth: 320)
    .padding(.vertical, 8)
  }
}

/// only validated, successfully published export selections are remembered.
@MainActor
final class GIFExportSettingsStore {
  static let frameRateKey = "gifferent.export.frameRate"
  static let speedKey = "gifferent.export.speed"
  private let defaults: UserDefaults?
  private(set) var frameRate: GIFCompressionFrameRate
  private(set) var playbackSpeed: Double

  init(defaults: UserDefaults? = nil) {
    self.defaults = defaults
    let storedRate = defaults.flatMap {
      GIFCompressionFrameRate(rawValue: $0.integer(forKey: Self.frameRateKey))
    }
    frameRate =
      storedRate.flatMap { GIFCompressionFrameRate.exportPresets.contains($0) ? $0 : nil } ?? .fps50
    let speed = defaults?.double(forKey: Self.speedKey) ?? 1
    playbackSpeed = GIFEditParameters.speedPresets.contains(speed) ? speed : 1
  }

  func remember(_ parameters: GIFEditParameters) {
    guard GIFCompressionFrameRate.exportPresets.contains(parameters.frameRate),
      GIFEditParameters.speedPresets.contains(parameters.playbackSpeed)
    else { return }
    frameRate = parameters.frameRate
    playbackSpeed = parameters.playbackSpeed
    defaults?.set(frameRate.rawValue, forKey: Self.frameRateKey)
    defaults?.set(playbackSpeed, forKey: Self.speedKey)
  }
}
