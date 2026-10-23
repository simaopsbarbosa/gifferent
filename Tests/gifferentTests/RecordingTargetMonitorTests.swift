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

  func testDisconnectedDisplayStopsDisplayAndRegionCapture() throws {
    let snapshot = RecordingTargetSnapshot(displayIDs: [2], visibleWindowIDs: [])
    let display = try XCTUnwrap(
      DisplayGeometry(
        id: 1,
        frameInGlobalPoints: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        pixelWidth: 1920,
        pixelHeight: 1080
      ))
    let region = RecordingTarget.region(
      try XCTUnwrap(
        SelectionGeometry(
          display: display,
          regionInDisplayPoints: CGRect(x: 10, y: 20, width: 100, height: 80)
        ))
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

  func testCaptureSelectionMapsToRecordingTargetWithoutLosingGeometry() throws {
    let display = try XCTUnwrap(
      DisplayGeometry(
        id: 7,
        frameInGlobalPoints: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
        pixelWidth: 3840,
        pixelHeight: 2160
      ))
    let geometry = try XCTUnwrap(
      SelectionGeometry(
        display: display,
        regionInDisplayPoints: CGRect(x: 30, y: 40, width: 500, height: 300)
      ))
    let target = RecordingTarget(selection: .region(geometry))

    XCTAssertEqual(target, .region(geometry))
    XCTAssertEqual(target.displayID, display.id)
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
