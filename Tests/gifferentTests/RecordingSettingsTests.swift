import Foundation
import XCTest

@testable import gifferent

@MainActor
final class RecordingSettingsTests: XCTestCase {
  func testCursorIsIncludedByDefault() {
    let store = RecordingSettingsStore(defaults: temporaryDefaults())

    XCTAssertTrue(store.showsCursor)
  }

  func testCursorPreferencePersistsAndRestores() {
    let defaults = temporaryDefaults()
    let store = RecordingSettingsStore(defaults: defaults)

    store.showsCursor = false

    XCTAssertFalse(defaults.bool(forKey: RecordingSettingsStore.cursorKey))
    XCTAssertFalse(RecordingSettingsStore(defaults: defaults).showsCursor)
  }

  func testDurationWarningTriggersAtThirtySecondsOnlyOnce() {
    var policy = RecordingWarningPolicy()
    policy.beginRecording()

    XCTAssertNil(policy.evaluate(elapsed: 29.9, workspaceBytes: 0, workspaceQuotaBytes: 1_000))
    XCTAssertEqual(
      policy.evaluate(elapsed: 30, workspaceBytes: 0, workspaceQuotaBytes: 1_000), .duration)
    XCTAssertNil(policy.evaluate(elapsed: 31, workspaceBytes: 0, workspaceQuotaBytes: 1_000))
  }

  func testWorkspaceWarningTriggersAtSeventyFivePercentOnlyOnce() {
    var policy = RecordingWarningPolicy()
    policy.beginRecording()

    XCTAssertNil(policy.evaluate(elapsed: 0, workspaceBytes: 749, workspaceQuotaBytes: 1_000))
    XCTAssertEqual(
      policy.evaluate(elapsed: 0, workspaceBytes: 750, workspaceQuotaBytes: 1_000),
      .workspaceSize
    )
    XCTAssertNil(policy.evaluate(elapsed: 0, workspaceBytes: 900, workspaceQuotaBytes: 1_000))
  }

  func testDismissalSuppressesFurtherWarningsUntilNextRecording() {
    var policy = RecordingWarningPolicy()
    policy.beginRecording()

    XCTAssertEqual(
      policy.evaluate(elapsed: 30, workspaceBytes: 0, workspaceQuotaBytes: 1_000), .duration)
    policy.dismiss()
    XCTAssertNil(policy.evaluate(elapsed: 31, workspaceBytes: 900, workspaceQuotaBytes: 1_000))

    policy.beginRecording()
    XCTAssertEqual(
      policy.evaluate(elapsed: 0, workspaceBytes: 750, workspaceQuotaBytes: 1_000),
      .workspaceSize
    )
  }

  func testWorkspaceByteUpdatesAreCoalescedToFourPerSecond() {
    let clock = ContinuousClock()
    let start = clock.now
    var throttle = RecordingWorkspaceByteUpdateThrottle()

    XCTAssertTrue(throttle.shouldPublish(at: start))
    XCTAssertFalse(throttle.shouldPublish(at: start.advanced(by: .milliseconds(100))))
    XCTAssertFalse(throttle.shouldPublish(at: start.advanced(by: .milliseconds(249))))
    XCTAssertTrue(throttle.shouldPublish(at: start.advanced(by: .milliseconds(250))))
  }

  private func temporaryDefaults() -> UserDefaults {
    let suiteName = "gifferent.recording-settings.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }
}
