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

  func testRecordingSettingsAndWarningDoNotStopCapture() {
    let app = XCUIApplication()
    app.launchArguments.append("--ui-testing")
    app.launch()

    let testWindow = app.windows["gifferent test menu"]
    XCTAssertTrue(testWindow.waitForExistence(timeout: 10))
    testWindow.buttons["recording-settings-button"].click()

    let settingsWindow = app.windows["recording settings"]
    XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
    let cursorToggle = settingsWindow.descendants(matching: .any)
      .matching(identifier: "include-cursor-toggle").firstMatch
    XCTAssertTrue(cursorToggle.exists)
    XCTAssertEqual(cursorToggle.label, "include cursor, included")
    cursorToggle.click()
    XCTAssertEqual(cursorToggle.label, "include cursor, hidden")
    settingsWindow.typeKey("w", modifierFlags: .command)

    testWindow.buttons["recording-action-button"].click()
    let selectionWindow = app.windows["capture selection"]
    XCTAssertTrue(selectionWindow.waitForExistence(timeout: 10))
    selectionWindow.buttons["select-display-button"].click()
    selectionWindow.buttons["confirm-selection-button"].click()
    waitForStatus("recording", in: testWindow)

    let fixtureState = testWindow.staticTexts["recording-cursor-fixture-state"]
    XCTAssertTrue(fixtureState.waitForExistence(timeout: 5))
    XCTAssertEqual(fixtureState.value as? String, "cursor hidden")

    testWindow.buttons["show-recording-warning-button"].click()
    let warning = testWindow.staticTexts["recording-warning"]
    XCTAssertTrue(warning.waitForExistence(timeout: 5))
    XCTAssertEqual(warning.value as? String, "recording has reached 30 seconds")
    waitForStatus("recording", in: testWindow)

    testWindow.buttons["dismiss-recording-warning-button"].click()
    XCTAssertFalse(warning.waitForExistence(timeout: 1))
    waitForStatus("recording", in: testWindow)

    testWindow.buttons["show-recording-warning-button"].click()
    XCTAssertFalse(warning.waitForExistence(timeout: 1))
    waitForStatus("recording", in: testWindow)
    testWindow.buttons["recording-action-button"].click()
    XCTAssertTrue(app.windows["gif preview"].waitForExistence(timeout: 10))
  }

  func testWorkspaceWarningDoesNotStopCapture() {
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

    testWindow.buttons["show-workspace-warning-button"].click()
    let warning = testWindow.staticTexts["recording-warning"]
    XCTAssertTrue(warning.waitForExistence(timeout: 5))
    XCTAssertEqual(warning.value as? String, "recording has reached 75% of its temporary space")
    waitForStatus("recording", in: testWindow)

    testWindow.buttons["dismiss-recording-warning-button"].click()
    XCTAssertFalse(warning.waitForExistence(timeout: 1))
    waitForStatus("recording", in: testWindow)
    testWindow.buttons["show-workspace-warning-button"].click()
    XCTAssertFalse(warning.waitForExistence(timeout: 1))
    waitForStatus("recording", in: testWindow)

    testWindow.buttons["recording-action-button"].click()
    XCTAssertTrue(app.windows["gif preview"].waitForExistence(timeout: 10))
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

  func testFixtureRegionSelectionAndCancellationRestoreLastSelection() {
    let app = XCUIApplication()
    app.launchArguments.append("--ui-testing")
    app.launch()

    let testWindow = app.windows["gifferent test menu"]
    XCTAssertTrue(testWindow.waitForExistence(timeout: 10))
    testWindow.buttons["select-capture-button"].click()

    let selectionWindow = app.windows["capture selection"]
    XCTAssertTrue(selectionWindow.waitForExistence(timeout: 10))
    selectionWindow.buttons["draw a region on this display"].click()

    let regionStart = selectionWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.32, dy: 0.32))
    let regionEnd = selectionWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.52, dy: 0.48))
    regionStart.press(forDuration: 0.1, thenDragTo: regionEnd)

    let confirmButton = selectionWindow.buttons["confirm-selection-button"]
    XCTAssertTrue(confirmButton.isEnabled, "drawing a region should enable confirmation")

    confirmButton.click()
    XCTAssertTrue(testWindow.staticTexts["selection-status"].waitForExistence(timeout: 5))
    let status = testWindow.staticTexts["selection-status"]
    XCTAssertEqual(status.value as? String, "region selected")

    testWindow.buttons["select-capture-button"].click()
    let restoredSelectionWindow = app.windows["capture selection"]
    XCTAssertTrue(restoredSelectionWindow.waitForExistence(timeout: 10))
    XCTAssertTrue(restoredSelectionWindow.buttons["confirm-selection-button"].isEnabled)

    restoredSelectionWindow.buttons["cancel-selection-button"].click()
    XCTAssertFalse(restoredSelectionWindow.waitForExistence(timeout: 5))
    waitForStatus("selection ready", in: testWindow)
    XCTAssertEqual(status.value as? String, "region selected")
  }

  func testFixtureWindowSelectionCanBeConfirmed() {
    let app = XCUIApplication()
    app.launchArguments.append("--ui-testing")
    app.launch()

    let testWindow = app.windows["gifferent test menu"]
    XCTAssertTrue(testWindow.waitForExistence(timeout: 10))
    testWindow.buttons["select-capture-button"].click()

    let selectionWindow = app.windows["capture selection"]
    XCTAssertTrue(selectionWindow.waitForExistence(timeout: 10))
    let windowPicker = selectionWindow.descendants(matching: .any)["select-window-picker"]
    XCTAssertTrue(windowPicker.waitForExistence(timeout: 5))
    windowPicker.click()
    let fixtureWindow = app.menuItems["gifferent fixture · fixture window"]
    XCTAssertTrue(fixtureWindow.waitForExistence(timeout: 5))
    fixtureWindow.click()

    XCTAssertTrue(selectionWindow.buttons["confirm-selection-button"].isEnabled)
    selectionWindow.buttons["confirm-selection-button"].click()

    let selectionStatus = testWindow.staticTexts["selection-status"]
    XCTAssertTrue(selectionStatus.waitForExistence(timeout: 5))
    XCTAssertEqual(selectionStatus.value as? String, "window selected")
  }

  func testSelectedWindowLossOpensUsablePartialPreview() {
    let app = XCUIApplication()
    app.launchArguments.append("--ui-testing")
    app.launch()

    let testWindow = app.windows["gifferent test menu"]
    XCTAssertTrue(testWindow.waitForExistence(timeout: 10))
    testWindow.buttons["recording-action-button"].click()

    let selectionWindow = app.windows["capture selection"]
    XCTAssertTrue(selectionWindow.waitForExistence(timeout: 10))
    selectionWindow.descendants(matching: .any)["select-window-picker"].click()
    let fixtureWindow = app.menuItems["gifferent fixture · fixture window"]
    XCTAssertTrue(fixtureWindow.waitForExistence(timeout: 5))
    fixtureWindow.click()
    selectionWindow.buttons["confirm-selection-button"].click()
    waitForStatus("recording", in: testWindow)

    testWindow.buttons["lose-selected-window-button"].click()
    let previewWindow = app.windows["gif preview"]
    XCTAssertTrue(previewWindow.waitForExistence(timeout: 10))
    XCTAssertTrue(waitForPreviewStatus("preview ready", in: previewWindow))
    XCTAssertTrue(previewWindow.staticTexts["preview-partial-status"].exists)
    previewWindow.buttons["copy-preview-button"].click()
    XCTAssertTrue(waitForPreviewAction("copied", in: previewWindow))
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
    selectionWindow.buttons["draw a region on this display"].click()
    let regionStart = selectionWindow.coordinate(
      withNormalizedOffset: CGVector(dx: 0.32, dy: 0.32))
    let regionEnd = selectionWindow.coordinate(
      withNormalizedOffset: CGVector(dx: 0.52, dy: 0.48))
    regionStart.press(forDuration: 0.1, thenDragTo: regionEnd)
    selectionWindow.buttons["confirm-selection-button"].click()

    let status = testWindow.staticTexts["app-status"]
    XCTAssertTrue(status.waitForExistence(timeout: 5))
    waitForStatus("recording", in: testWindow)
    let recordingFrameState = testWindow.staticTexts["recording-frame-fixture-state"]
    XCTAssertTrue(recordingFrameState.waitForExistence(timeout: 5))
    XCTAssertTrue(
      waitForValue(containing: "visible=true", in: recordingFrameState),
      "fixture state: \(recordingFrameState.value as? String ?? "<nil>")")
    testWindow.buttons["recording-action-button"].click()

    let previewWindow = app.windows["gif preview"]
    XCTAssertTrue(previewWindow.waitForExistence(timeout: 10))
    XCTAssertTrue(
      waitForValue(containing: "hidden", in: recordingFrameState),
      "fixture state: \(recordingFrameState.value as? String ?? "<nil>")")
    XCTAssertTrue(waitForPreviewStatus("preview ready", in: previewWindow))
    XCTAssertTrue(previewWindow.staticTexts["preview-size"].exists)
    XCTAssertTrue(previewWindow.staticTexts["preview-duration"].exists)
    XCTAssertEqual(previewWindow.staticTexts["preview-dimensions"].value as? String, "16 by 16")
    let animatedPreview = previewWindow.images["animated-gif-preview"]
    XCTAssertTrue(animatedPreview.waitForExistence(timeout: 5))
    XCTAssertEqual(animatedPreview.elementType, .image)
    XCTAssertEqual(animatedPreview.label, "animated gif preview")

    let startHandle = previewWindow.descendants(matching: .any)
      .matching(identifier: "trim-start-handle").firstMatch
    let endHandle = previewWindow.descendants(matching: .any)
      .matching(identifier: "trim-end-handle").firstMatch
    XCTAssertTrue(startHandle.exists)
    XCTAssertEqual(startHandle.label, "trim start")
    XCTAssertTrue(endHandle.exists)
    XCTAssertEqual(endHandle.label, "trim end")
    let speedSlider = previewWindow.sliders["playback-speed-slider"]
    XCTAssertTrue(speedSlider.exists)
    XCTAssertTrue(previewWindow.buttons["loop-once-button"].exists)
    XCTAssertTrue(previewWindow.buttons["loop-forever-button"].exists)

    previewWindow.buttons["loop-once-button"].click()
    XCTAssertTrue(waitForPreviewAction("gif updated", in: previewWindow))
    speedSlider.adjust(toNormalizedSliderPosition: 0.666)
    XCTAssertTrue(
      waitForValue(containing: "1.5×", in: previewWindow.staticTexts["playback-speed-value"])
    )
    XCTAssertTrue(waitForEnabled(previewWindow.buttons["copy-preview-button"]))
    let previewScrollView = previewWindow.scrollViews.firstMatch
    XCTAssertTrue(previewScrollView.exists)
    previewScrollView.swipeUp()
    XCTAssertTrue(previewWindow.buttons["copy-preview-button"].isHittable)
    XCTAssertTrue(previewWindow.buttons["save-preview-button"].isHittable)
    XCTAssertTrue(previewWindow.buttons["discard-preview-button"].isHittable)
    XCTAssertTrue(previewWindow.buttons["close-preview-button"].isHittable)

    previewWindow.typeKey("c", modifierFlags: .command)
    XCTAssertTrue(waitForPreviewAction("copied", in: previewWindow))
    previewWindow.typeKey("s", modifierFlags: .command)
    XCTAssertTrue(waitForPreviewAction("saved", in: previewWindow))
    XCTAssertTrue(FileManager.default.fileExists(atPath: savedFixture.path))

    previewWindow.buttons["close-preview-button"].click()
    XCTAssertFalse(previewWindow.waitForExistence(timeout: 5))
    waitForStatus("selection ready", in: testWindow)
  }

  func testCompressionTargetsAreVisibleAndUnavailableWithoutBackend() {
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

    let github = previewWindow.buttons["compression-destination-github"]
    XCTAssertTrue(github.exists)
    XCTAssertTrue(github.label.contains("GitHub"), github.label)
    XCTAssertTrue(github.label.contains("9 MB target"), github.label)
    XCTAssertTrue(github.label.contains("10 MB published maximum"), github.label)

    let discord = previewWindow.buttons["compression-destination-discord"]
    XCTAssertTrue(discord.exists)
    XCTAssertTrue(discord.label.contains("Discord"), discord.label)
    XCTAssertTrue(discord.label.contains("18 MB target"), discord.label)
    XCTAssertTrue(discord.label.contains("20 MB published maximum"), discord.label)

    XCTAssertTrue(previewWindow.staticTexts["compression-unavailable-status"].exists)
    let quality = previewWindow.sliders["compression-quality-slider"]
    XCTAssertTrue(quality.exists)
    XCTAssertEqual(quality.label, "gifski quality")
    XCTAssertTrue(previewWindow.staticTexts["compression-quality-value"].exists)
    XCTAssertTrue(
      waitForValue(containing: "90", in: previewWindow.staticTexts["compression-quality-value"])
    )
    XCTAssertFalse(previewWindow.buttons["compress-preview-button"].exists)
    XCTAssertTrue(waitForEnabled(previewWindow.buttons["copy-preview-button"]))
    XCTAssertTrue(waitForEnabled(previewWindow.buttons["save-preview-button"]))
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

  private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "isEnabled == true"), object: element)
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }
}
