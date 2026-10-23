import CoreGraphics
import XCTest

@testable import gifferent

final class RecordingFrameGeometryTests: XCTestCase {
  func testRegionFrameMapsTopLeftDisplayPointsToAppKitCoordinates() throws {
    let frame = try XCTUnwrap(
      RecordingFrameGeometry.regionFrame(
        CGRect(x: 20, y: 15, width: 80, height: 40),
        displayFrame: CGRect(x: -100, y: 50, width: 400, height: 300)))

    XCTAssertEqual(frame, CGRect(x: -80, y: 295, width: 80, height: 40))
  }

  func testOverlayPanelLeavesRoomOutsideTargetAndAboveItsTopEdge() throws {
    let target = CGRect(x: 100, y: 200, width: 320, height: 180)
    let frame = try XCTUnwrap(RecordingFrameGeometry.panelFrame(around: target))
    let targetRect = try XCTUnwrap(RecordingFrameGeometry.targetRect(inPanelFor: target))

    XCTAssertEqual(
      frame,
      CGRect(
        x: 96,
        y: 196,
        width: 328,
        height: 180 + RecordingFrameGeometry.outsideInset * 2
          + RecordingFrameGeometry.labelHeight))
    XCTAssertEqual(targetRect.origin.x, RecordingFrameGeometry.outsideInset)
    XCTAssertEqual(targetRect.origin.y, RecordingFrameGeometry.labelHeight)
    XCTAssertEqual(targetRect.size, target.size)
  }

  func testInvalidGeometryDoesNotCreateAnOverlay() {
    XCTAssertNil(
      RecordingFrameGeometry.regionFrame(
        CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10),
        displayFrame: CGRect(x: 0, y: 0, width: 100, height: 100)))
    XCTAssertNil(RecordingFrameGeometry.panelFrame(around: .zero))
  }
}
