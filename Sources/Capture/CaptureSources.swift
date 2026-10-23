import CoreGraphics
import Foundation
import ScreenCaptureKit

enum ScreenRecordingAuthorization: Sendable {
  case granted
  case needsPermission
}

@MainActor
protocol ScreenRecordingPermissionProviding {
  func preflight() -> ScreenRecordingAuthorization
  func request() -> ScreenRecordingAuthorization
}

struct SystemScreenRecordingPermission: ScreenRecordingPermissionProviding {
  func preflight() -> ScreenRecordingAuthorization {
    CGPreflightScreenCaptureAccess() ? .granted : .needsPermission
  }

  func request() -> ScreenRecordingAuthorization {
    CGRequestScreenCaptureAccess() ? .granted : .needsPermission
  }
}

struct CaptureDisplaySource: Equatable, Sendable {
  let id: CGDirectDisplayID
  let frame: CGRect
  let widthInPoints: Int
  let heightInPoints: Int
}

struct CaptureWindowSource: Equatable, Sendable {
  let id: CGWindowID
  let frame: CGRect
  let title: String?
  let applicationName: String?
  let applicationBundleIdentifier: String?
}

struct CaptureSourceInventory: Equatable, Sendable {
  let displays: [CaptureDisplaySource]
  let windows: [CaptureWindowSource]

  func display(id: CGDirectDisplayID) throws -> CaptureDisplaySource {
    guard let display = displays.first(where: { $0.id == id }) else {
      throw CaptureSourceError.displayUnavailable
    }
    return display
  }

  func window(id: CGWindowID) throws -> CaptureWindowSource {
    guard let window = windows.first(where: { $0.id == id }) else {
      throw CaptureSourceError.windowUnavailable
    }
    return window
  }
}

enum CaptureSourceError: Error, Equatable {
  case permissionRequired
  case listingUnavailable
  case displayUnavailable
  case windowUnavailable
}

@MainActor
protocol CaptureSourceListing {
  func availableSources() async throws -> CaptureSourceInventory
}

struct ScreenCaptureKitSourceListing: CaptureSourceListing {
  func availableSources() async throws -> CaptureSourceInventory {
    let ownBundleIdentifier = Bundle.main.bundleIdentifier

    return try await withCheckedThrowingContinuation { continuation in
      SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) {
        content, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }

        guard let content else {
          continuation.resume(throwing: CaptureSourceError.listingUnavailable)
          return
        }

        let displays = content.displays.map { display in
          CaptureDisplaySource(
            id: display.displayID,
            frame: display.frame,
            widthInPoints: display.width,
            heightInPoints: display.height
          )
        }
        let windows = content.windows.compactMap { window -> CaptureWindowSource? in
          let owner = window.owningApplication
          if let ownBundleIdentifier, owner?.bundleIdentifier == ownBundleIdentifier {
            return nil
          }
          return CaptureWindowSource(
            id: window.windowID,
            frame: window.frame,
            title: window.title,
            applicationName: owner?.applicationName,
            applicationBundleIdentifier: owner?.bundleIdentifier
          )
        }
        continuation.resume(returning: CaptureSourceInventory(displays: displays, windows: windows))
      }
    }
  }
}

@MainActor
final class CaptureSourceService {
  private let permission: any ScreenRecordingPermissionProviding
  private let listing: any CaptureSourceListing

  init(
    permission: (any ScreenRecordingPermissionProviding)? = nil,
    listing: (any CaptureSourceListing)? = nil
  ) {
    self.permission = permission ?? SystemScreenRecordingPermission()
    self.listing = listing ?? ScreenCaptureKitSourceListing()
  }

  func authorizationStatus() -> ScreenRecordingAuthorization {
    permission.preflight()
  }

  func requestPermission() -> ScreenRecordingAuthorization {
    permission.request()
  }

  func availableSources() async throws -> CaptureSourceInventory {
    guard permission.preflight() == .granted else {
      throw CaptureSourceError.permissionRequired
    }
    let sources = try await listing.availableSources()
    try Task.checkCancellation()
    return sources
  }
}
