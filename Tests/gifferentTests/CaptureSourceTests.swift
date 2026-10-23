import CoreGraphics
import XCTest

@testable import gifferent

@MainActor
final class CaptureSourceTests: XCTestCase {
  func testDeniedPermissionDoesNotListSourcesOrRequestAccess() async {
    let permission = FakePermission(status: .needsPermission)
    let listing = FakeListing(result: .success(.empty))
    let service = CaptureSourceService(permission: permission, listing: listing)

    do {
      _ = try await service.availableSources()
      XCTFail("expected permission error")
    } catch {
      XCTAssertEqual(error as? CaptureSourceError, .permissionRequired)
    }
    XCTAssertEqual(permission.requestCount, 0)
    XCTAssertEqual(listing.listCount, 0)

    XCTAssertEqual(service.requestPermission(), .needsPermission)
    XCTAssertEqual(permission.requestCount, 1)
  }

  func testGrantedPermissionListsDisplayAndWindowSnapshots() async throws {
    let inventory = CaptureSourceInventory.sample
    let listing = FakeListing(result: .success(inventory))
    let service = CaptureSourceService(
      permission: FakePermission(status: .granted), listing: listing)

    XCTAssertEqual(service.authorizationStatus(), .granted)
    let sources = try await service.availableSources()
    XCTAssertEqual(sources, inventory)
    XCTAssertEqual(try sources.display(id: 7), inventory.displays[0])
    XCTAssertEqual(try sources.window(id: 23), inventory.windows[0])
    XCTAssertEqual(listing.listCount, 1)
  }

  func testPermissionRequestCanGrantAccessBeforeListing() async throws {
    let permission = FakePermission(status: .needsPermission)
    permission.requestStatus = .granted
    let listing = FakeListing(result: .success(.sample))
    let service = CaptureSourceService(permission: permission, listing: listing)

    XCTAssertEqual(service.requestPermission(), .granted)
    XCTAssertEqual(permission.requestCount, 1)
    let sources = try await service.availableSources()
    XCTAssertEqual(sources, .sample)
    XCTAssertEqual(listing.listCount, 1)
  }

  func testListingFailureIsPropagated() async {
    let service = CaptureSourceService(
      permission: FakePermission(status: .granted),
      listing: FakeListing(result: .failure(FakeListingError.unavailable))
    )

    do {
      _ = try await service.availableSources()
      XCTFail("expected listing failure")
    } catch {
      XCTAssertEqual(error as? FakeListingError, .unavailable)
    }
  }

  func testMissingTargetsMapToUnavailableErrors() {
    let sources = CaptureSourceInventory.sample

    XCTAssertThrowsError(try sources.display(id: 8)) { error in
      XCTAssertEqual(error as? CaptureSourceError, .displayUnavailable)
    }
    XCTAssertThrowsError(try sources.window(id: 24)) { error in
      XCTAssertEqual(error as? CaptureSourceError, .windowUnavailable)
    }
  }

  func testPermissionLossBlocksAnotherListing() async throws {
    let permission = FakePermission(status: .granted)
    let listing = FakeListing(result: .success(.sample))
    let service = CaptureSourceService(permission: permission, listing: listing)

    _ = try await service.availableSources()
    permission.status = .needsPermission

    do {
      _ = try await service.availableSources()
      XCTFail("expected permission error")
    } catch {
      XCTAssertEqual(error as? CaptureSourceError, .permissionRequired)
    }
    XCTAssertEqual(listing.listCount, 1)
  }
}

@MainActor
private final class FakePermission: ScreenRecordingPermissionProviding {
  var status: ScreenRecordingAuthorization
  var requestStatus: ScreenRecordingAuthorization?
  private(set) var requestCount = 0

  init(status: ScreenRecordingAuthorization) {
    self.status = status
  }

  func preflight() -> ScreenRecordingAuthorization { status }

  func request() -> ScreenRecordingAuthorization {
    requestCount += 1
    if let requestStatus {
      status = requestStatus
    }
    return status
  }
}

@MainActor
private final class FakeListing: CaptureSourceListing {
  let result: Result<CaptureSourceInventory, Error>
  private(set) var listCount = 0

  init(result: Result<CaptureSourceInventory, Error>) {
    self.result = result
  }

  func availableSources() async throws -> CaptureSourceInventory {
    listCount += 1
    return try result.get()
  }
}

private enum FakeListingError: Error {
  case unavailable
}

extension CaptureSourceInventory {
  fileprivate static let empty = CaptureSourceInventory(displays: [], windows: [])

  fileprivate static let sample = CaptureSourceInventory(
    displays: [
      CaptureDisplaySource(
        id: 7, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
        widthInPoints: 1920, heightInPoints: 1080)
    ],
    windows: [
      CaptureWindowSource(
        id: 23, frame: CGRect(x: -1000, y: 50, width: 700, height: 500),
        title: "sample", applicationName: "sample app",
        applicationBundleIdentifier: "example.app")
    ]
  )
}
