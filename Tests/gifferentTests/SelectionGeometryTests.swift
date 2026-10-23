import CoreGraphics
import XCTest

@testable import gifferent

final class SelectionGeometryTests: XCTestCase {
  func testOneAndTwoTimesScalesProduceExpectedPixels() throws {
    let oneTimes = try XCTUnwrap(display(id: 1, width: 100, height: 80, scale: 1))
    let twoTimes = try XCTUnwrap(display(id: 2, width: 100, height: 80, scale: 2))
    let rect = CGRect(x: 10, y: 5, width: 30, height: 20)

    let oneSelection = try XCTUnwrap(
      SelectionGeometry(display: oneTimes, regionInDisplayPoints: rect))
    let twoSelection = try XCTUnwrap(
      SelectionGeometry(display: twoTimes, regionInDisplayPoints: rect))
    XCTAssertEqual(
      oneSelection.capturePixels(on: oneTimes),
      CapturePixelRegion(x: 10, y: 5, width: 30, height: 20))
    XCTAssertEqual(
      twoSelection.capturePixels(on: twoTimes),
      CapturePixelRegion(x: 20, y: 10, width: 60, height: 40))
  }

  func testGlobalDisplayOriginDoesNotOffsetLocalCapturePixels() throws {
    let screen = try XCTUnwrap(display(id: 1, x: -1440, y: 120, width: 100, height: 80, scale: 2))
    let selection = try XCTUnwrap(
      SelectionGeometry(
        display: screen, regionInDisplayPoints: CGRect(x: 5, y: 7, width: 10, height: 12)))

    XCTAssertEqual(
      selection.capturePixels(on: screen), CapturePixelRegion(x: 10, y: 14, width: 20, height: 24))
  }

  func testFractionalEdgesRoundOutwardAndStayWithinDisplay() throws {
    let screen = try XCTUnwrap(display(id: 1, width: 100, height: 80, scale: 2))
    let selection = try XCTUnwrap(
      SelectionGeometry(
        display: screen, regionInDisplayPoints: CGRect(x: 0.25, y: 0.75, width: 10.5, height: 9.5)))
    XCTAssertEqual(
      selection.capturePixels(on: screen), CapturePixelRegion(x: 0, y: 1, width: 22, height: 20))

    let edgeSelection = try XCTUnwrap(
      SelectionGeometry(
        display: screen,
        regionInDisplayPoints: CGRect(x: 99.75, y: 79.75, width: 0.25, height: 0.25)))
    XCTAssertEqual(
      edgeSelection.capturePixels(on: screen),
      CapturePixelRegion(x: 199, y: 159, width: 1, height: 1))
  }

  func testMovingClampsInsideDisplayWithoutChangingSize() throws {
    let screen = try XCTUnwrap(display(id: 1, width: 100, height: 80, scale: 1))
    let selection = try XCTUnwrap(
      SelectionGeometry(
        display: screen, regionInDisplayPoints: CGRect(x: 10, y: 20, width: 30, height: 25)))

    XCTAssertEqual(
      selection.moved(to: CGPoint(x: -20, y: 90))?.regionInDisplayPoints,
      CGRect(x: 0, y: 55, width: 30, height: 25))
    XCTAssertNil(selection.moved(to: CGPoint(x: CGFloat.nan, y: 0)))
  }

  func testResizingClampsFarEdgesAndRejectsZeroSize() throws {
    let screen = try XCTUnwrap(display(id: 1, width: 100, height: 80, scale: 1))
    let selection = try XCTUnwrap(
      SelectionGeometry(
        display: screen, regionInDisplayPoints: CGRect(x: 10, y: 20, width: 30, height: 25)))

    XCTAssertEqual(
      selection.resized(to: CGSize(width: 200, height: 100))?.regionInDisplayPoints,
      CGRect(x: 10, y: 20, width: 90, height: 60))
    XCTAssertNil(selection.resized(to: CGSize(width: 0, height: 20)))
  }

  func testDraggedTopLeftCornerKeepsBottomRightFixed() throws {
    let screen = try XCTUnwrap(display(id: 1, width: 100, height: 80, scale: 2))
    let selection = try XCTUnwrap(
      SelectionGeometry(
        display: screen, regionInDisplayPoints: CGRect(x: 10, y: 20, width: 30, height: 25)))

    XCTAssertEqual(
      selection.resized(dragging: .topLeft, to: CGPoint(x: 5, y: 7))?.regionInDisplayPoints,
      CGRect(x: 5, y: 7, width: 35, height: 38))
    XCTAssertEqual(
      selection.resized(dragging: .topLeft, to: CGPoint(x: -50, y: -50))?.regionInDisplayPoints,
      CGRect(x: 0, y: 0, width: 40, height: 45))
  }

  func testDraggedBottomRightCornerKeepsTopLeftFixedAndHasPositiveSize() throws {
    let screen = try XCTUnwrap(display(id: 1, width: 100, height: 80, scale: 2))
    let selection = try XCTUnwrap(
      SelectionGeometry(
        display: screen, regionInDisplayPoints: CGRect(x: 10, y: 20, width: 30, height: 25)))

    XCTAssertEqual(
      selection.resized(dragging: .bottomRight, to: CGPoint(x: 120, y: 100))?.regionInDisplayPoints,
      CGRect(x: 10, y: 20, width: 90, height: 60))
    XCTAssertEqual(
      selection.resized(dragging: .bottomRight, to: CGPoint(x: -10, y: -10))?.regionInDisplayPoints,
      CGRect(x: 10, y: 20, width: 0.5, height: 0.5))
    XCTAssertNil(selection.resized(dragging: .bottomRight, to: CGPoint(x: CGFloat.nan, y: 0)))
  }

  func testOtherDraggedCornersKeepTheirOppositeCornersFixed() throws {
    let screen = try XCTUnwrap(display(id: 1, width: 100, height: 80, scale: 1))
    let selection = try XCTUnwrap(
      SelectionGeometry(
        display: screen, regionInDisplayPoints: CGRect(x: 10, y: 20, width: 30, height: 25)))

    XCTAssertEqual(
      selection.resized(dragging: .topRight, to: CGPoint(x: 60, y: 5))?.regionInDisplayPoints,
      CGRect(x: 10, y: 5, width: 50, height: 40))
    XCTAssertEqual(
      selection.resized(dragging: .bottomLeft, to: CGPoint(x: 5, y: 60))?.regionInDisplayPoints,
      CGRect(x: 5, y: 20, width: 35, height: 40))
  }

  func testInvalidRegionsAndDisplayGeometryAreRejected() throws {
    let screen = try XCTUnwrap(display(id: 1, width: 100, height: 80, scale: 1))
    XCTAssertNil(
      SelectionGeometry(
        display: screen, regionInDisplayPoints: CGRect(x: 0, y: 0, width: 0, height: 10)))
    XCTAssertNil(
      SelectionGeometry(
        display: screen, regionInDisplayPoints: CGRect(x: -1, y: 0, width: 10, height: 10)))
    XCTAssertNil(
      SelectionGeometry(
        display: screen, regionInDisplayPoints: CGRect(x: 95, y: 0, width: 10, height: 10)))
    XCTAssertNil(display(id: 1, width: 0, height: 80, scale: 1))
    XCTAssertNil(
      DisplayGeometry(
        id: 1, frameInGlobalPoints: CGRect(x: 0, y: 0, width: 100, height: 80), pixelWidth: 0,
        pixelHeight: 80))
  }

  func testChangedDisplayGeometryInvalidatesExistingSelection() throws {
    let original = try XCTUnwrap(display(id: 1, width: 100, height: 80, scale: 2))
    let selection = try XCTUnwrap(
      SelectionGeometry(
        display: original, regionInDisplayPoints: CGRect(x: 10, y: 10, width: 20, height: 20)))

    XCTAssertTrue(selection.isValid(on: original))
    for changed in [
      display(id: 2, width: 100, height: 80, scale: 2),
      display(id: 1, x: -100, width: 100, height: 80, scale: 2),
      display(id: 1, width: 120, height: 80, scale: 2),
      display(id: 1, width: 100, height: 80, scale: 1),
    ] {
      let screen = try XCTUnwrap(changed)
      XCTAssertFalse(selection.isValid(on: screen))
      XCTAssertNil(selection.capturePixels(on: screen))
    }
  }

  private func display(
    id: UInt32,
    x: CGFloat = 0,
    y: CGFloat = 0,
    width: CGFloat,
    height: CGFloat,
    scale: Int
  ) -> DisplayGeometry? {
    DisplayGeometry(
      id: id,
      frameInGlobalPoints: CGRect(x: x, y: y, width: width, height: height),
      pixelWidth: Int(width) * scale,
      pixelHeight: Int(height) * scale
    )
  }
}
