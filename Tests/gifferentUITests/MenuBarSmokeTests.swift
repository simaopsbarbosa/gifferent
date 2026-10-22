import XCTest

@MainActor
final class MenuBarSmokeTests: XCTestCase {
  func testLaunchShowsIdleMenuAndQuitAction() {
    let app = XCUIApplication()
    app.launchArguments.append("--ui-testing")
    app.launch()

    let menuBarItem = app.menuBarItems["gifferent"]
    XCTAssertTrue(menuBarItem.waitForExistence(timeout: 10))
    menuBarItem.click()

    XCTAssertTrue(app.staticTexts["idle"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["quit"].exists)
  }
}
