import XCTest

@MainActor
final class MenuBarSmokeTests: XCTestCase {
  func testLaunchShowsIdleContentAndQuitAction() {
    let app = XCUIApplication()
    app.launchArguments.append("--ui-testing")
    app.launch()

    let testWindow = app.windows["gifferent test menu"]
    XCTAssertTrue(testWindow.waitForExistence(timeout: 10))
    XCTAssertTrue(testWindow.staticTexts["app-status"].exists)

    let quitButton = testWindow.buttons["quit-button"]
    XCTAssertTrue(quitButton.exists)
    quitButton.click()
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
  }

  func testShortcutSettingsOpenFromMenu() {
    let app = XCUIApplication()
    app.launchArguments.append("--ui-testing")
    app.launch()

    let testWindow = app.windows["gifferent test menu"]
    XCTAssertTrue(testWindow.waitForExistence(timeout: 10))
    XCTAssertTrue(testWindow.buttons["select-capture-button"].exists)
    testWindow.buttons["shortcuts-button"].click()

    let settingsWindow = app.windows["shortcuts"]
    XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
    XCTAssertTrue(settingsWindow.buttons["hotkey-capture-button"].exists)
    XCTAssertTrue(settingsWindow.buttons["hotkey-record-button"].exists)
  }

  func testFixtureDisplaySelectionReturnsToMenu() {
    let app = XCUIApplication()
    app.launchArguments.append("--ui-testing")
    app.launch()

    let testWindow = app.windows["gifferent test menu"]
    XCTAssertTrue(testWindow.waitForExistence(timeout: 10))
    testWindow.buttons["select-capture-button"].click()

    let selectionWindow = app.windows["capture selection"]
    XCTAssertTrue(selectionWindow.waitForExistence(timeout: 10))
    selectionWindow.buttons["select-display-button"].click()
    selectionWindow.buttons["confirm-selection-button"].click()

    let selectionStatus = testWindow.staticTexts["selection-status"]
    XCTAssertTrue(selectionStatus.waitForExistence(timeout: 5))
    waitForStatus("selection ready", in: testWindow)
    XCTAssertEqual(testWindow.buttons["recording-action-button"].label, "start recording")
  }

  func testRecordingActionSelectsTargetStartsAndRetainsCapturedFramesUntilDiscard() {
    let app = XCUIApplication()
    app.launchArguments.append("--ui-testing")
    app.launch()

    let testWindow = app.windows["gifferent test menu"]
    XCTAssertTrue(testWindow.waitForExistence(timeout: 10))
    testWindow.buttons["recording-action-button"].click()

    let selectionWindow = app.windows["capture selection"]
    XCTAssertTrue(selectionWindow.waitForExistence(timeout: 10))
    selectionWindow.buttons["select-display-button"].click()
    selectionWindow.buttons["confirm-selection-button"].click()

    let status = testWindow.staticTexts["app-status"]
    XCTAssertTrue(status.waitForExistence(timeout: 5))
    waitForStatus("recording", in: testWindow)
    testWindow.buttons["recording-action-button"].click()
    waitForStatus("frames captured; GIF preview is not available yet", in: testWindow)

    testWindow.buttons["recording-action-button"].click()
    waitForStatus("selection ready", in: testWindow)
  }

  private func waitForStatus(
    _ expected: String,
    in testWindow: XCUIElement,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", expected),
      object: testWindow.staticTexts["app-status"]
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
  }
}
