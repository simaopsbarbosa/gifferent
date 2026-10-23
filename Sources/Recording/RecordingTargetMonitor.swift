import CoreGraphics

enum RecordingTarget: Equatable {
  case display(CGDirectDisplayID)
  case region(SelectionGeometry)
  case window(CGWindowID)

  init(selection: CaptureSelection) {
    switch selection {
    case .display(let id):
      self = .display(id)
    case .window(let id):
      self = .window(id)
    case .region(let geometry):
      self = .region(geometry)
    }
  }

  var displayID: CGDirectDisplayID? {
    switch self {
    case .display(let id): id
    case .region(let geometry): geometry.display.id
    case .window: nil
    }
  }
}

enum CaptureTerminationReason: Equatable {
  case userStopped
  case windowUnavailable
  case displayDisconnected
  case permissionLost
  case streamFailed
}

struct RecordingTargetSnapshot: Equatable {
  let displayIDs: Set<CGDirectDisplayID>
  let visibleWindowIDs: Set<CGWindowID>
}

enum RecordingTargetMonitor {
  static func lossReason(
    for target: RecordingTarget,
    in snapshot: RecordingTargetSnapshot
  ) -> CaptureTerminationReason? {
    switch target {
    case .display(let id):
      return snapshot.displayIDs.contains(id) ? nil : .displayDisconnected
    case .region(let geometry):
      return snapshot.displayIDs.contains(geometry.display.id) ? nil : .displayDisconnected
    case .window(let id):
      return snapshot.visibleWindowIDs.contains(id) ? nil : .windowUnavailable
    }
  }
}

struct RecordingStopSummary: Equatable {
  let reason: CaptureTerminationReason
  let usableFrameCount: Int

  var hasPartialResult: Bool {
    guard usableFrameCount > 0 else { return false }
    return reason == .windowUnavailable || reason == .displayDisconnected
  }
}
