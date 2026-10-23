import CoreGraphics

enum RecordingTarget: Equatable {
  case display(CGDirectDisplayID)
  case region(displayID: CGDirectDisplayID, sourceRectInPoints: CGRect)
  case window(CGWindowID)
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
    case .display(let id), .region(let id, _):
      return snapshot.displayIDs.contains(id) ? nil : .displayDisconnected
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
