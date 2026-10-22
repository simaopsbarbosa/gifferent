import XCTest

final class FoundationTests: XCTestCase {
  func testAppIsConfiguredWithoutDockPresence() {
    XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool, true)
  }
}
