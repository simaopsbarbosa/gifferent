import CoreGraphics
import XCTest

@testable import gifferent

final class RecordingTargetMonitorTests: XCTestCase {
  func testWindowRemainsAvailableWhenItMovesBetweenDisplays() {
    let target = RecordingTarget.window(42)
    let snapshot = RecordingTargetSnapshot(displayIDs: [2], visibleWindowIDs: [42])
    XCTAssertNil(RecordingTargetMonitor.lossReason(for: target, in: snapshot))
  }

  func testMissingWindowStopsCapture() {
    let snapshot = RecordingTargetSnapshot(displayIDs: [1], visibleWindowIDs: [])
    XCTAssertEqual(
      RecordingTargetMonitor.lossReason(for: .window(42), in: snapshot),
      .windowUnavailable
    )
  }

  func testDisconnectedDisplayStopsDisplayAndRegionCapture() {
    let snapshot = RecordingTargetSnapshot(displayIDs: [2], visibleWindowIDs: [])
    let region = RecordingTarget.region(
      displayID: 1,
      sourceRectInPoints: CGRect(x: 10, y: 20, width: 100, height: 80)
    )
    XCTAssertEqual(
      RecordingTargetMonitor.lossReason(for: .display(1), in: snapshot),
      .displayDisconnected
    )
    XCTAssertEqual(
      RecordingTargetMonitor.lossReason(for: region, in: snapshot),
      .displayDisconnected
    )
  }

  func testPartialResultRequiresAUsableFrame() {
    XCTAssertFalse(
      RecordingStopSummary(reason: .windowUnavailable, usableFrameCount: 0)
        .hasPartialResult)
    XCTAssertTrue(
      RecordingStopSummary(reason: .displayDisconnected, usableFrameCount: 1)
        .hasPartialResult)
    XCTAssertFalse(
      RecordingStopSummary(reason: .userStopped, usableFrameCount: 1)
        .hasPartialResult)
  }
}
