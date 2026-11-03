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
