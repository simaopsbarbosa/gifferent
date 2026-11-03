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
        x: target.minX - RecordingFrameGeometry.outsideInset,
        y: target.minY - RecordingFrameGeometry.outsideInset,
        width: target.width + RecordingFrameGeometry.outsideInset * 2,
        height: 180 + RecordingFrameGeometry.outsideInset * 2
          + RecordingFrameGeometry.labelHeight))
    XCTAssertEqual(targetRect.origin.x, RecordingFrameGeometry.outsideInset)
    XCTAssertEqual(
      targetRect.origin.y,
      RecordingFrameGeometry.labelHeight + RecordingFrameGeometry.outsideInset)
    XCTAssertEqual(targetRect.size, target.size)

    // Convert the SwiftUI top-left rect back into AppKit screen coordinates.
    // Its bounds must coincide with the capture target.
    let targetInScreen = CGRect(
      x: frame.minX + targetRect.minX,
      y: frame.minY + frame.height - targetRect.maxY,
      width: targetRect.width,
      height: targetRect.height
    )
    XCTAssertEqual(targetInScreen, target)
    XCTAssertEqual(targetInScreen.minX - RecordingFrameGeometry.outsideInset, frame.minX)
    XCTAssertEqual(targetInScreen.minY - RecordingFrameGeometry.outsideInset, frame.minY)
  }

  func testOutlineStrokesLeaveGapAroundFractionalTarget() {
    let target = CGRect(x: 6.25, y: 24.75, width: 100.5, height: 50.25)
    for (offset, width): (CGFloat, CGFloat) in [(2.5, 3), (0.5, 1)] {
      let centerline = RecordingFrameGeometry.outlineRect(around: target, centerOffset: offset)
      let innerEdge = centerline.insetBy(dx: width / 2, dy: width / 2)
      XCTAssertLessThanOrEqual(innerEdge.minX, target.minX - RecordingFrameGeometry.outlineGap)
      XCTAssertLessThanOrEqual(innerEdge.minY, target.minY - RecordingFrameGeometry.outlineGap)
      XCTAssertGreaterThanOrEqual(innerEdge.maxX, target.maxX + RecordingFrameGeometry.outlineGap)
      XCTAssertGreaterThanOrEqual(innerEdge.maxY, target.maxY + RecordingFrameGeometry.outlineGap)
    }
  }

  func testInvalidGeometryDoesNotCreateAnOverlay() {
    XCTAssertNil(
      RecordingFrameGeometry.regionFrame(
        CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10),
        displayFrame: CGRect(x: 0, y: 0, width: 100, height: 100)))
    XCTAssertNil(RecordingFrameGeometry.panelFrame(around: .zero))
  }
}
