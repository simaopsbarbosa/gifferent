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

  func testRecordingActionOpensPreviewAndKeepsExportAfterClose() {
    let savedFixture = FileManager.default.temporaryDirectory
      .appendingPathComponent("gifferent-preview-ui-save.gif")
    try? FileManager.default.removeItem(at: savedFixture)
    defer { try? FileManager.default.removeItem(at: savedFixture) }

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

    let previewWindow = app.windows["gif preview"]
    XCTAssertTrue(previewWindow.waitForExistence(timeout: 10))
    XCTAssertTrue(waitForPreviewStatus("preview ready", in: previewWindow))
    XCTAssertTrue(previewWindow.staticTexts["preview-size"].exists)
    XCTAssertTrue(previewWindow.staticTexts["preview-duration"].exists)
    XCTAssertEqual(previewWindow.staticTexts["preview-dimensions"].value as? String, "16 by 16")
    let animatedPreview = previewWindow.images["animated-gif-preview"]
    XCTAssertTrue(animatedPreview.waitForExistence(timeout: 5))
    XCTAssertEqual(animatedPreview.elementType, .image)
    XCTAssertEqual(animatedPreview.label, "animated gif preview")

    previewWindow.buttons["copy-preview-button"].click()
    XCTAssertTrue(waitForPreviewAction("copied", in: previewWindow))
    previewWindow.buttons["save-preview-button"].click()
    XCTAssertTrue(waitForPreviewAction("saved", in: previewWindow))

    previewWindow.buttons["close-preview-button"].click()
    XCTAssertFalse(previewWindow.waitForExistence(timeout: 5))
    waitForStatus("selection ready", in: testWindow)
  }

  func testUnexportedPreviewCanStayOpenOrBeDiscardedAfterConfirmation() {
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
    waitForStatus("recording", in: testWindow)
    testWindow.buttons["recording-action-button"].click()

    let previewWindow = app.windows["gif preview"]
    XCTAssertTrue(previewWindow.waitForExistence(timeout: 10))
    XCTAssertTrue(waitForPreviewStatus("preview ready", in: previewWindow))
    previewWindow.buttons["close-preview-button"].click()
    let keepButton = app.buttons["keep-preview-button"]
    XCTAssertTrue(keepButton.waitForExistence(timeout: 5))
    keepButton.click()
    XCTAssertTrue(previewWindow.exists)

    previewWindow.buttons["discard-preview-button"].click()
    let discardButton = app.buttons["confirm-preview-discard-button"]
    XCTAssertTrue(discardButton.waitForExistence(timeout: 5))
    discardButton.click()
    XCTAssertFalse(previewWindow.waitForExistence(timeout: 5))
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
    XCTAssertTrue(
      waitForValue(containing: "visible=true", in: fixtureState),
      "fixture state: \(fixtureState.value as? String ?? "<nil>")\n\(app.debugDescription)")
    XCTAssertTrue(
      (fixtureState.value as? String)?.contains("app-window=true") == true,
      "fixture state: \(fixtureState.value as? String ?? "<nil>")\n\(app.debugDescription)")
    XCTAssertTrue(
      (fixtureState.value as? String)?.contains("ax-window=true") == true,
      "fixture state: \(fixtureState.value as? String ?? "<nil>")\n\(app.debugDescription)")

    let frameWindow = app.descendants(matching: .any)
      .matching(identifier: "recording-frame-window").firstMatch
    XCTAssertTrue(frameWindow.waitForExistence(timeout: 5))
    let label = frameWindow.descendants(matching: .any)
      .matching(identifier: "recording-frame-label").firstMatch
    XCTAssertTrue(label.waitForExistence(timeout: 5))
    XCTAssertEqual(label.label, "recording")
    XCTAssertEqual(label.value as? String, "recording")
    let originalFrame = label.frame

    testWindow.buttons["move-recording-frame-button"].click()
    let deadline = Date().addingTimeInterval(5)
    while label.frame.minX <= originalFrame.minX && Date() < deadline {
      Thread.sleep(forTimeInterval: 0.05)
    }
    XCTAssertGreaterThan(label.frame.minX, originalFrame.minX)

    testWindow.buttons["hide-recording-frame-button"].click()
    XCTAssertTrue(
      waitForValue(containing: "hidden", in: fixtureState),
      "fixture state: \(fixtureState.value as? String ?? "<nil>")\n\(app.debugDescription)")
    let removalDeadline = Date().addingTimeInterval(5)
    while frameWindow.exists && Date() < removalDeadline {
      Thread.sleep(forTimeInterval: 0.05)
    }
    XCTAssertFalse(frameWindow.exists, "\(app.debugDescription)")
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

  private func waitForPreviewStatus(_ expected: String, in window: XCUIElement) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", expected),
      object: window.staticTexts["preview-status"]
    )
    return XCTWaiter.wait(for: [expectation], timeout: 10) == .completed
  }

  private func waitForPreviewAction(_ expected: String, in window: XCUIElement) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", expected),
      object: window.staticTexts["preview-action-status"]
    )
    return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
  }
}
