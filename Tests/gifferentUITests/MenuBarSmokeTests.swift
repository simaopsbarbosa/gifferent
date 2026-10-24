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

  func testRecordingFrameFixtureShowsMovesAndHidesAccessibly() {
    let app = XCUIApplication()
    app.launchArguments.append("--ui-testing")
    app.launch()

    let testWindow = app.windows["gifferent test menu"]
    XCTAssertTrue(testWindow.waitForExistence(timeout: 10))
    testWindow.buttons["show-recording-frame-button"].click()

    let fixtureState = testWindow.staticTexts["recording-frame-fixture-state"]
    XCTAssertTrue(fixtureState.waitForExistence(timeout: 5))
    XCTAssertTrue(waitForValue(containing: "visible=true", in: fixtureState))
    XCTAssertTrue((fixtureState.value as? String)?.contains("app-window=true") == true)

    let frameWindow = app.descendants(matching: .any)
      .matching(identifier: "recording-frame-window").firstMatch
    XCTAssertTrue(frameWindow.waitForExistence(timeout: 5))
    let label = app.descendants(matching: .staticText)
      .matching(identifier: "recording-frame-label").firstMatch
    XCTAssertTrue(label.waitForExistence(timeout: 5))
    XCTAssertEqual(label.label, "recording")
    let originalFrame = label.frame

    testWindow.buttons["move-recording-frame-button"].click()
    let deadline = Date().addingTimeInterval(5)
    while label.frame.minX <= originalFrame.minX && Date() < deadline {
      Thread.sleep(forTimeInterval: 0.05)
    }
    XCTAssertGreaterThan(label.frame.minX, originalFrame.minX)

    testWindow.buttons["hide-recording-frame-button"].click()
    XCTAssertTrue(waitForValue(containing: "hidden", in: fixtureState))
    XCTAssertFalse(frameWindow.waitForExistence(timeout: 1))
  }

  private func waitForValue(
    containing expected: String,
    in element: XCUIElement,
    timeout: TimeInterval = 5
  ) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value CONTAINS %@", expected), object: element)
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
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
