import AppKit
import SwiftUI

@MainActor
final class RecordingFrameOverlayController {
  private(set) var isVisible = false
  private var panel: RecordingFramePanel?
  private var trackingTask: Task<Void, Never>?

  func show(region: SelectionGeometry) {
    guard let screen = NSScreen.screens.first(where: { $0.displayID == region.display.id }),
      let frame = RecordingFrameGeometry.regionFrame(
        region.regionInDisplayPoints, displayFrame: screen.frame)
    else {
      hide()
      return
    }
    show(frame: frame)
  }

  func show(windowID: CGWindowID) {
    hide()
    guard let frame = currentWindowFrame(windowID: windowID) else { return }
    show(frame: frame)
    trackingTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(150))
        guard let self, !Task.isCancelled else { return }
        guard let frame = self.currentWindowFrame(windowID: windowID) else {
          self.hide()
          return
        }
        self.panel?.setTargetFrame(frame)
      }
    }
  }

  func hide() {
    trackingTask?.cancel()
    trackingTask = nil
    if let panel {
      let accessibilityWindows = (NSApp.accessibilityWindows() as? [NSWindow] ?? [])
        .filter { $0 !== panel }
      NSApp.setAccessibilityWindows(accessibilityWindows)
      NSAccessibility.post(element: panel, notification: .uiElementDestroyed)
    }
    panel?.orderOut(nil)
    panel?.close()
    panel = nil
    isVisible = false
  }

  #if DEBUG
    var fixtureStateDescription: String {
      guard let panel else { return "hidden" }
      let isAccessibilityWindow =
        (NSApp.accessibilityWindows() as? [NSWindow] ?? []).contains { $0 === panel }
      return
        "visible=\(panel.isVisible), app-window=\(NSApp.windows.contains { $0 === panel }), ax-window=\(isAccessibilityWindow), x=\(Int(panel.frame.minX))"
    }

    func showFixture(frame: CGRect) {
      show(frame: frame)
    }

    func moveFixture(to frame: CGRect) {
      panel?.setTargetFrame(frame)
    }
  #endif

  private func show(frame: CGRect) {
    hide()
    guard let panel = RecordingFramePanel(targetFrame: frame) else { return }
    self.panel = panel
    panel.orderFrontRegardless()
    var accessibilityWindows = NSApp.accessibilityWindows() ?? []
    if !accessibilityWindows.contains(where: { ($0 as? NSWindow) === panel }) {
      accessibilityWindows.append(panel)
      NSApp.setAccessibilityWindows(accessibilityWindows)
    }
    isVisible = true
  }

  private func currentWindowFrame(windowID: CGWindowID) -> CGRect? {
    guard
      let windowInfo = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID)
        as? [[String: Any]],
      let info = windowInfo.first,
      let bounds = info[kCGWindowBounds as String] as? CGRect,
      let screen = NSScreen.screens
        .filter({ screen in screen.displayFrameInQuartzCoordinates.intersects(bounds) })
        .max(by: {
          $0.displayFrameInQuartzCoordinates.intersection(bounds).area
            < $1.displayFrameInQuartzCoordinates.intersection(bounds).area
        }),
      let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        as? NSNumber
    else { return nil }

    let displayBounds = CGDisplayBounds(displayNumber.uint32Value)
    let localQuartzY = bounds.minY - displayBounds.minY
    let localQuartzX = bounds.minX - displayBounds.minX
    let cocoaFrame = CGRect(
      x: screen.frame.minX + localQuartzX,
      y: screen.frame.minY + screen.frame.height - localQuartzY - bounds.height,
      width: bounds.width,
      height: bounds.height
    )
    return cocoaFrame.width > 0 && cocoaFrame.height > 0 ? cocoaFrame : nil
  }
}

@MainActor
private final class RecordingFramePanel: NSPanel {
  init?(targetFrame: CGRect) {
    guard let frame = RecordingFrameGeometry.panelFrame(around: targetFrame),
      let targetRect = RecordingFrameGeometry.targetRect(inPanelFor: targetFrame)
    else { return nil }
    super.init(
      contentRect: frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    title = "recording frame"
    setAccessibilityElement(true)
    setAccessibilityEnabled(true)
    setAccessibilityLabel("recording frame")
    setAccessibilityTitle("recording frame")
    setAccessibilityIdentifier("recording-frame-window")
    setAccessibilityRole(.window)
    level = .statusBar
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    isFloatingPanel = true
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    ignoresMouseEvents = true
    isReleasedWhenClosed = false
    let hostingView = NSHostingView(rootView: RecordingFrameView(targetRect: targetRect))
    hostingView.setAccessibilityElement(true)
    hostingView.setAccessibilityRole(.group)
    hostingView.setAccessibilityLabel("recording")
    hostingView.setAccessibilityValue("recording")
    hostingView.setAccessibilityIdentifier("recording-frame-label")
    contentView = hostingView
    if let contentView {
      setAccessibilityContents([contentView])
    }
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  func setTargetFrame(_ frame: CGRect) {
    guard let panelFrame = RecordingFrameGeometry.panelFrame(around: frame),
      let targetRect = RecordingFrameGeometry.targetRect(inPanelFor: frame)
    else { return }
    setFrame(panelFrame, display: true)
    if let hostingView = contentView as? NSHostingView<RecordingFrameView> {
      hostingView.rootView = RecordingFrameView(targetRect: targetRect)
    }
  }
}

private struct RecordingFrameView: View {
  let targetRect: CGRect

  var body: some View {
    let outerOutline = targetRect.insetBy(dx: -2.5, dy: -2.5)
    let innerOutline = targetRect.insetBy(dx: -0.5, dy: -0.5)

    ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: 2)
        .stroke(.white, lineWidth: 3)
        .frame(width: outerOutline.width, height: outerOutline.height)
        .position(x: outerOutline.midX, y: outerOutline.midY)
        .accessibilityHidden(true)

      RoundedRectangle(cornerRadius: 1)
        .stroke(.black, lineWidth: 1)
        .frame(width: innerOutline.width, height: innerOutline.height)
        .position(x: innerOutline.midX, y: innerOutline.midY)
        .accessibilityHidden(true)

      Text("recording")
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white, lineWidth: 1))
        .position(x: targetRect.minX + 31, y: targetRect.minY / 2)
        .accessibilityLabel("recording")
        .accessibilityIdentifier("recording-frame-caption")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("recording frame")
    .accessibilityIdentifier("recording-frame")
    .allowsHitTesting(false)
  }
}

extension NSScreen {
  fileprivate var displayID: CGDirectDisplayID? {
    (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
  }

  fileprivate var displayFrameInQuartzCoordinates: CGRect {
    guard let displayID else { return .zero }
    return CGDisplayBounds(displayID)
  }
}

extension CGRect {
  fileprivate var area: CGFloat { width * height }
}
