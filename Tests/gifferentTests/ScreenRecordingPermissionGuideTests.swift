import XCTest

@testable import gifferent

@MainActor
final class ScreenRecordingPermissionGuideTests: XCTestCase {
  func testOpeningGuideOnlyPreflightsAndDoesNotRequestPermission() {
    let permission = PermissionStub()
    let model = ScreenRecordingPermissionGuideModel(permission: permission)

    XCTAssertEqual(model.state, .needsPermission)
    XCTAssertEqual(permission.preflightCount, 1)
    XCTAssertEqual(permission.requestCount, 0)

    model.refresh()
    XCTAssertEqual(permission.preflightCount, 2)
    XCTAssertEqual(permission.requestCount, 0)
  }

  func testRequestAndRecheckRecoverAfterGrant() {
    let permission = PermissionStub()
    var grants = 0
    let model = ScreenRecordingPermissionGuideModel(permission: permission) {
      true
    } onGranted: {
      grants += 1
    }

    model.requestPermission()
    XCTAssertEqual(permission.requestCount, 1)
    XCTAssertTrue(model.hasRequestedPermission)
    XCTAssertEqual(model.state, .needsPermission)
    XCTAssertEqual(grants, 0)

    permission.authorization = .granted
    model.refresh()
    model.refresh()
    XCTAssertEqual(model.state, .granted)
    XCTAssertEqual(grants, 1)

    permission.authorization = .needsPermission
    model.refresh()
    XCTAssertEqual(model.state, .needsPermission)

    permission.authorization = .granted
    model.refresh()
    XCTAssertEqual(grants, 2)
  }

  func testSettingsFailureCanRecoverOnRecheck() {
    let permission = PermissionStub()
    var openCount = 0
    let model = ScreenRecordingPermissionGuideModel(permission: permission) {
      openCount += 1
      return false
    }

    model.openSettings()
    XCTAssertEqual(openCount, 1)
    XCTAssertEqual(model.state, .settingsUnavailable)

    model.refresh()
    XCTAssertEqual(model.state, .needsPermission)
  }

  func testImmediateGrantAndSuccessfulSettingsOpen() {
    let permission = PermissionStub()
    var openCount = 0
    var grants = 0
    let model = ScreenRecordingPermissionGuideModel(permission: permission) {
      openCount += 1
      return true
    } onGranted: {
      grants += 1
    }

    model.openSettings()
    XCTAssertEqual(openCount, 1)
    XCTAssertEqual(model.state, .needsPermission)

    permission.authorization = .granted
    model.requestPermission()
    XCTAssertEqual(model.state, .granted)
    XCTAssertEqual(grants, 1)
  }
}

@MainActor
private final class PermissionStub: ScreenRecordingPermissionProviding {
  var authorization: ScreenRecordingAuthorization = .needsPermission
  var preflightCount = 0
  var requestCount = 0

  func preflight() -> ScreenRecordingAuthorization {
    preflightCount += 1
    return authorization
  }

  func request() -> ScreenRecordingAuthorization {
    requestCount += 1
    return authorization
  }
}
