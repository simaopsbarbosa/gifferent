import AppKit
import XCTest

@testable import gifferent

final class FoundationTests: XCTestCase {
  @MainActor
  func testHostedUnitTestsCannotStartTheProductionRuntime() {
    XCTAssertTrue(GifferentRuntime.isUnitTestHost)
    XCTAssertTrue(
      GifferentRuntime.recordingWorkspaceURL().path.contains(
        "gifferent-unit-host-\(ProcessInfo.processInfo.processIdentifier)"))
    GifferentRuntime.shared.start()
    XCTAssertEqual(GifferentRuntime.shared.recordingCoordinator.state, .idle)
  }

  @MainActor
  func testPreviewHeightLocksAfterInitialFitWhileWidthRemainsResizable() {
    let runtime = GifferentRuntime.shared
    let controller = GIFPreviewWindowController(
      runtime: runtime, coordinator: runtime.recordingCoordinator)
    defer { controller.closeAfterCleanup() }
    let window = controller.window
    XCTAssertEqual(window.contentMinSize.height, window.contentMaxSize.height)
    let titleBarHeight = window.frame.height - window.contentRect(forFrameRect: window.frame).height
    let availableHeight = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 10_000
    controller.fitInitialReadyContent(height: 600)
    XCTAssertEqual(window.contentMinSize.height, min(600, availableHeight - 32 - titleBarHeight))
    let fittedHeight = window.frame.height
    XCTAssertTrue(window.delegate === controller)
    // exercise the actual resize delegate rather than only inspecting size constraints.
    for proposedHeight in [fittedHeight - 150, fittedHeight + 200] {
      let resized = window.delegate?.windowWillResize?(
        window, to: NSSize(width: 700, height: proposedHeight))
      XCTAssertEqual(resized?.height, fittedHeight)
      XCTAssertEqual(resized?.width, 700)
    }
    XCTAssertEqual(window.contentMinSize.height, window.contentMaxSize.height)
    XCTAssertEqual(
      window.contentMinSize.height, window.contentRect(forFrameRect: window.frame).height)
    XCTAssertTrue(window.styleMask.contains(.resizable))
    XCTAssertLessThan(window.contentMinSize.width, window.contentMaxSize.width)
    controller.fitInitialReadyContent(height: 900)
    XCTAssertEqual(window.frame.height, fittedHeight)
    if let screen = window.screen ?? NSScreen.main {
      XCTAssertLessThanOrEqual(fittedHeight, screen.visibleFrame.height - 32)
    }
  }

  func testAppIsConfiguredWithoutDockPresence() {
    XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool, true)
  }

  func testAppExplainsWhyItNeedsScreenCaptureAccess() {
    XCTAssertEqual(
      Bundle.main.object(forInfoDictionaryKey: "NSScreenCaptureUsageDescription") as? String,
      "gifferent captures the display or window you select to create a local gif."
    )
  }

  func testPreviewDitherIsBoundedDeterministicAndMoves() throws {
    XCTAssertNil(PreviewDitherArtwork.image(size: .zero, time: 0, dark: true))
    let size = CGSize(width: 560, height: 280)
    let first = try XCTUnwrap(PreviewDitherArtwork.image(size: size, time: 0, dark: true))
    let repeated = try XCTUnwrap(PreviewDitherArtwork.image(size: size, time: 0, dark: true))
    let later = try XCTUnwrap(PreviewDitherArtwork.image(size: size, time: 10, dark: true))
    let light = try XCTUnwrap(PreviewDitherArtwork.image(size: size, time: 0, dark: false))
    XCTAssertLessThanOrEqual(first.width, 256)
    XCTAssertLessThanOrEqual(first.height, 128)
    let pixels = try XCTUnwrap(first.dataProvider?.data) as Data
    XCTAssertEqual(pixels, try XCTUnwrap(repeated.dataProvider?.data) as Data)
    XCTAssertNotEqual(pixels, try XCTUnwrap(later.dataProvider?.data) as Data)
    XCTAssertNotEqual(pixels, try XCTUnwrap(light.dataProvider?.data) as Data)
  }
}
