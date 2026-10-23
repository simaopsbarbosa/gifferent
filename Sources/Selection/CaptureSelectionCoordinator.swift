import AppKit
import CoreGraphics
import SwiftUI

enum CaptureSelection: Equatable {
  case display(CGDirectDisplayID)
  case window(CGWindowID)
  case region(SelectionGeometry)
}

enum CaptureSelectionRestoration {
  static func validSelection(
    _ previous: CaptureSelection?,
    inventory: CaptureSourceInventory,
    displays: [DisplayGeometry]
  ) -> CaptureSelection? {
    guard let previous else { return nil }
    switch previous {
    case .display(let id):
      return displays.contains(where: { $0.id == id }) ? previous : nil
    case .window(let id):
      return inventory.windows.contains(where: { $0.id == id }) ? previous : nil
    case .region(let region):
      return displays.contains(where: { region.isValid(on: $0) }) ? previous : nil
    }
  }
}

enum SelectionPresentationError: Error, Equatable {
  case permissionRequired
  case noDisplays
  case sourceUnavailable
  case screenshotUnavailable
}

struct SelectionScreen {
  let geometry: DisplayGeometry
  let frame: CGRect
  let snapshot: CGImage
}

@MainActor
final class CaptureSelectionCoordinator: ObservableObject {
  @Published private(set) var selection: CaptureSelection?
  @Published private(set) var inventory = CaptureSourceInventory(displays: [], windows: [])
  @Published private(set) var presentationError: SelectionPresentationError?

  private let sourceService: CaptureSourceService
  private var windows: [SelectionOverlayWindow] = []
  private var screens: [CGDirectDisplayID: SelectionScreen] = [:]
  private var onSelection: ((CaptureSelection) -> Void)?
  private var onCancel: (() -> Void)?
  private var onError: ((SelectionPresentationError) -> Void)?
  private var presentationTask: Task<Void, Never>?
  private var previousApplication: NSRunningApplication?

  init(sourceService: CaptureSourceService = CaptureSourceService()) {
    self.sourceService = sourceService
  }

  /// the callback receives a target only after the user confirms it.
  func present(
    restoring previousSelection: CaptureSelection? = nil,
    onSelection: @escaping (CaptureSelection) -> Void,
    onCancel: @escaping () -> Void = {},
    onError: @escaping (SelectionPresentationError) -> Void = { _ in }
  ) {
    cancel(notify: false)
    self.onSelection = onSelection
    self.onCancel = onCancel
    self.onError = onError
    presentationError = nil
    previousApplication = NSWorkspace.shared.frontmostApplication

    presentationTask = Task { [weak self] in
      guard let self else { return }
      do {
        let inventory = try await sourceService.availableSources()
        try Task.checkCancellation()
        self.inventory = inventory
        let availableScreens = try self.makeScreens(for: inventory)
        self.screens = Dictionary(
          uniqueKeysWithValues: availableScreens.map {
            ($0.geometry.id, $0)
          })
        self.selection = CaptureSelectionRestoration.validSelection(
          previousSelection,
          inventory: inventory,
          displays: availableScreens.map(\.geometry)
        )
        self.showWindows(for: availableScreens)
      } catch is CancellationError {
        return
      } catch CaptureSourceError.permissionRequired {
        self.fail(.permissionRequired)
      } catch let error as SelectionPresentationError {
        self.fail(error)
      } catch {
        self.fail(.sourceUnavailable)
      }
    }
  }

  #if DEBUG
    func presentFixture(
      restoring previousSelection: CaptureSelection? = nil,
      onSelection: @escaping (CaptureSelection) -> Void,
      onCancel: @escaping () -> Void = {},
      onError: @escaping (SelectionPresentationError) -> Void = { _ in }
    ) {
      cancel(notify: false)
      self.onSelection = onSelection
      self.onCancel = onCancel
      self.onError = onError
      presentationError = nil
      previousApplication = NSWorkspace.shared.frontmostApplication

      guard
        let screen = NSScreen.screens.first,
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
          as? NSNumber,
        let geometry = DisplayGeometry(
          id: number.uint32Value,
          frameInGlobalPoints: screen.frame,
          pixelWidth: 100,
          pixelHeight: 100
        ),
        let context = CGContext(
          data: nil,
          width: 100,
          height: 100,
          bitsPerComponent: 8,
          bytesPerRow: 0,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
      else {
        fail(.noDisplays)
        return
      }
      context.setFillColor(CGColor(gray: 0.4, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
      guard let image = context.makeImage() else {
        fail(.screenshotUnavailable)
        return
      }
      let fixtureScreen = SelectionScreen(geometry: geometry, frame: screen.frame, snapshot: image)
      inventory = CaptureSourceInventory(
        displays: [
          CaptureDisplaySource(
            id: geometry.id,
            frame: screen.frame,
            widthInPoints: Int(screen.frame.width),
            heightInPoints: Int(screen.frame.height)
          )
        ],
        windows: []
      )
      screens = [geometry.id: fixtureScreen]
      selection = CaptureSelectionRestoration.validSelection(
        previousSelection,
        inventory: inventory,
        displays: [geometry]
      )
      showWindows(for: [fixtureScreen])
    }
  #endif

  func cancel() {
    cancel(notify: true)
  }

  func confirm() {
    guard let selection, isAvailable(selection) else {
      fail(.sourceUnavailable)
      return
    }
    let callback = onSelection
    cancel(notify: false)
    callback?(selection)
  }

  func selectDisplay(_ id: CGDirectDisplayID) {
    guard screens[id] != nil else { return }
    selection = .display(id)
  }

  func selectWindow(_ id: CGWindowID) {
    guard inventory.windows.contains(where: { $0.id == id }) else { return }
    selection = .window(id)
  }

  func selectRegion(_ region: SelectionGeometry) {
    guard let screen = screens[region.display.id],
      region.isValid(on: screen.geometry)
    else { return }
    selection = .region(region)
  }

  func reselect() {
    selection = nil
  }

  func screen(for id: CGDirectDisplayID) -> SelectionScreen? {
    screens[id]
  }

  private func isAvailable(_ selection: CaptureSelection) -> Bool {
    CaptureSelectionRestoration.validSelection(
      selection,
      inventory: inventory,
      displays: screens.values.map(\.geometry)
    ) != nil
  }

  private func makeScreens(for inventory: CaptureSourceInventory) throws -> [SelectionScreen] {
    var result: [SelectionScreen] = []
    for screen in NSScreen.screens {
      guard
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
          as? NSNumber,
        let source = inventory.displays.first(where: { $0.id == number.uint32Value })
      else { continue }
      guard
        let geometry = DisplayGeometry(
          id: source.id,
          frameInGlobalPoints: screen.frame,
          pixelWidth: CGDisplayPixelsWide(source.id),
          pixelHeight: CGDisplayPixelsHigh(source.id)
        ),
        let snapshot = CGDisplayCreateImage(source.id)
      else { throw SelectionPresentationError.screenshotUnavailable }
      result.append(SelectionScreen(geometry: geometry, frame: screen.frame, snapshot: snapshot))
    }
    guard !result.isEmpty else {
      throw inventory.displays.isEmpty
        ? SelectionPresentationError.noDisplays : SelectionPresentationError.screenshotUnavailable
    }
    return result
  }

  private func showWindows(for screens: [SelectionScreen]) {
    for screen in screens {
      let window = SelectionOverlayWindow(contentRect: screen.frame)
      window.title = "capture selection"
      window.contentView = NSHostingView(
        rootView: CaptureSelectionOverlayView(coordinator: self, screen: screen)
      )
      windows.append(window)
      window.makeKeyAndOrderFront(nil)
    }
    NSApp.activate(ignoringOtherApps: true)
    windows.first?.makeKey()
  }

  private func fail(_ error: SelectionPresentationError) {
    let callback = onError
    cancel(notify: false)
    presentationError = error
    callback?(error)
  }

  private func cancel(notify: Bool) {
    presentationTask?.cancel()
    presentationTask = nil
    let closingWindows = windows
    for window in closingWindows {
      window.orderOut(nil)
    }
    windows.removeAll()
    // close after the button event finishes so its hosting view stays alive during the callback.
    DispatchQueue.main.async {
      for window in closingWindows {
        window.close()
      }
    }
    screens.removeAll()
    selection = nil
    inventory = CaptureSourceInventory(displays: [], windows: [])
    let cancelCallback = onCancel
    onSelection = nil
    onCancel = nil
    onError = nil
    previousApplication?.activate(options: [])
    previousApplication = nil
    if notify { cancelCallback?() }
  }
}

private final class SelectionOverlayWindow: NSWindow {
  init(contentRect: CGRect) {
    super.init(
      contentRect: contentRect,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    level = .statusBar
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    isOpaque = true
    backgroundColor = .black
    hasShadow = false
    acceptsMouseMovedEvents = true
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}
