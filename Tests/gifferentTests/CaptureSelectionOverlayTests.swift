import CoreGraphics
import XCTest

@testable import gifferent

final class CaptureSelectionOverlayTests: XCTestCase {
  func testRestorationRejectsMissingOrChangedDisplay() throws {
    let original = try XCTUnwrap(
      DisplayGeometry(
        id: 12,
        frameInGlobalPoints: CGRect(x: 0, y: 0, width: 100, height: 100),
        pixelWidth: 200,
        pixelHeight: 200
      ))
    let changed = try XCTUnwrap(
      DisplayGeometry(
        id: 12,
        frameInGlobalPoints: CGRect(x: 0, y: 0, width: 120, height: 100),
        pixelWidth: 240,
        pixelHeight: 200
      ))
    let region = try XCTUnwrap(
      SelectionGeometry(
        display: original,
        regionInDisplayPoints: CGRect(x: 10, y: 10, width: 50, height: 50)
      ))
    let inventory = CaptureSourceInventory(displays: [], windows: [])

    XCTAssertEqual(
      CaptureSelectionRestoration.validSelection(
        .region(region), inventory: inventory, displays: [original]),
      .region(region)
    )
    XCTAssertNil(
      CaptureSelectionRestoration.validSelection(
        .region(region), inventory: inventory, displays: [changed]))
    XCTAssertNil(
      CaptureSelectionRestoration.validSelection(
        .display(99), inventory: inventory, displays: [original]))
  }

  func testRestorationKeepsOnlyListedWindow() {
    let inventory = CaptureSourceInventory(
      displays: [],
      windows: [
        CaptureWindowSource(
          id: 7,
          frame: CGRect(x: 0, y: 0, width: 20, height: 20),
          title: "sample",
          applicationName: "sample app",
          applicationBundleIdentifier: "example.sample"
        )
      ]
    )

    XCTAssertEqual(
      CaptureSelectionRestoration.validSelection(
        .window(7), inventory: inventory, displays: []), .window(7))
    XCTAssertNil(
      CaptureSelectionRestoration.validSelection(
        .window(8), inventory: inventory, displays: []))
  }

  func testMagnifierTracksRequestedPixelAtScreenEdges() throws {
    let geometry = try XCTUnwrap(
      DisplayGeometry(
        id: 3,
        frameInGlobalPoints: CGRect(x: 0, y: 0, width: 20, height: 20),
        pixelWidth: 40,
        pixelHeight: 40
      ))
    let context = try XCTUnwrap(
      CGContext(
        data: nil,
        width: 40,
        height: 40,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ))
    let image = try XCTUnwrap(context.makeImage())
    let screen = SelectionScreen(
      geometry: geometry, frame: geometry.frameInGlobalPoints,
      bottomSafeAreaInset: 0,
      snapshot: image)

    let topLeft = try XCTUnwrap(screen.magnifierCrop(at: .zero))
    XCTAssertEqual(topLeft.image.width, 21)
    XCTAssertEqual(topLeft.image.height, 21)
    XCTAssertEqual(topLeft.focus, .zero)

    let bottomRight = try XCTUnwrap(screen.magnifierCrop(at: CGPoint(x: 20, y: 20)))
    XCTAssertEqual(bottomRight.focus, CGPoint(x: 20, y: 20))
  }

  func testSelectionControlsReserveSpaceBelowVisibleFrame() {
    let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let visibleFrame = CGRect(x: 0, y: 70, width: 1440, height: 800)

    XCTAssertEqual(
      SelectionScreen.bottomSafeAreaInset(screenFrame: frame, visibleFrame: visibleFrame), 70)
    XCTAssertEqual(
      SelectionScreen.bottomSafeAreaInset(
        screenFrame: frame,
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)),
      0
    )
  }
}
