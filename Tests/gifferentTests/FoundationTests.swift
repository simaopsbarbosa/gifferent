import XCTest

final class FoundationTests: XCTestCase {
  func testAppIsConfiguredWithoutDockPresence() {
    XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool, true)
  }

  func testAppExplainsWhyItNeedsScreenCaptureAccess() {
    XCTAssertEqual(
      Bundle.main.object(forInfoDictionaryKey: "NSScreenCaptureUsageDescription") as? String,
      "gifferent captures the display or window you select to create a local gif."
    )
  }
}
