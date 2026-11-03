import CoreGraphics
import SwiftUI

struct CaptureSelectionOverlayView: View {
  @ObservedObject var coordinator: CaptureSelectionCoordinator
  let screen: SelectionScreen

  @State private var draftRegion: CGRect?
  @State private var dragStart: CGPoint?
  @State private var dragIntent: RegionDragIntent?
  @State private var magnifierPoint: CGPoint?

  private var displaySize: CGSize { screen.geometry.localBounds.size }

  private var selectedRegion: SelectionGeometry? {
    guard case .region(let region) = coordinator.selection,
      region.display.id == screen.geometry.id
    else { return nil }
    return region
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      Image(decorative: screen.snapshot, scale: 1, orientation: .up)
        .resizable()
        .frame(width: displaySize.width, height: displaySize.height)
        .accessibilityHidden(true)

      Color.black.opacity(0.16)
        .contentShape(Rectangle())
        .gesture(regionGesture)

      if case .display(let id) = coordinator.selection, id == screen.geometry.id {
        Rectangle()
          .strokeBorder(.white, lineWidth: 3)
          .padding(2)
          .allowsHitTesting(false)
          .accessibilityLabel("this display selected")
      }

      if let region = draftRegion ?? selectedRegion?.regionInDisplayPoints {
        regionOutline(region)
          .allowsHitTesting(false)
      }

      if let magnifierPoint {
        cornerMagnifier(at: magnifierPoint)
          .allowsHitTesting(false)
      }
    }
    .frame(width: displaySize.width, height: displaySize.height)
    .overlay(alignment: .bottomLeading) {
      controls
        .padding(16)
        .padding(.bottom, screen.bottomSafeAreaInset)
    }
    .clipped()
    .onExitCommand { coordinator.cancel() }
  }

  private var controls: some View {
    HStack(spacing: 10) {
      Button("display") { coordinator.selectDisplay(screen.geometry.id) }
        .accessibilityLabel("select this display")
        .accessibilityIdentifier("select-display-button")

      Menu {
        Button("choose a window") {}.disabled(true)
        ForEach(coordinator.inventory.windows, id: \.id) { window in
          Button {
            coordinator.selectWindow(window.id)
          } label: {
            if selectedWindowID == window.id {
              Label(windowLabel(window), systemImage: "checkmark")
            } else {
              Text(windowLabel(window))
            }
          }
        }
      } label: {
        Text(selectedWindowLabel)
      }
      .accessibilityLabel("select a window")
      .accessibilityIdentifier("select-window-picker")

      Button("region") {
        draftRegion = nil
        coordinator.reselect()
      }
      .accessibilityLabel("draw a region on this display")

      Text(selectionDescription)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
        .frame(maxWidth: 220)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("capture target")
        .accessibilityValue(selectionDescription)
        .accessibilityIdentifier("capture-target-description")

      Divider().frame(height: 18)

      Button("use selection") { coordinator.confirm() }
        .disabled(coordinator.selection == nil)
        .keyboardShortcut(.return, modifiers: [])
        .accessibilityHint("confirm the selected capture target")
        .accessibilityIdentifier("confirm-selection-button")

      Button("cancel") { coordinator.cancel() }
        .keyboardShortcut(.escape, modifiers: [])
        .accessibilityIdentifier("cancel-selection-button")
    }
    .buttonStyle(.bordered)
    .padding(10)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    .accessibilityElement(children: .contain)
  }

  private func windowLabel(_ window: CaptureWindowSource) -> String {
    let application = window.applicationName ?? "window"
    guard let title = window.title, !title.isEmpty else { return application }
    return "\(application) · \(title)"
  }

  private var selectedWindowID: CGWindowID? {
    guard case .window(let id) = coordinator.selection else { return nil }
    return id
  }

  private var selectedWindowLabel: String {
    guard let id = selectedWindowID,
      let window = coordinator.inventory.windows.first(where: { $0.id == id })
    else { return "choose a window" }
    return windowLabel(window)
  }

  private var selectionDescription: String {
    switch coordinator.selection {
    case .display(let id):
      return id == screen.geometry.id ? "this display selected" : "another display selected"
    case .window(let id):
      guard let window = coordinator.inventory.windows.first(where: { $0.id == id }) else {
        return "window selected"
      }
      return "\(windowLabel(window)) selected"
    case .region(let region):
      return region.display.id == screen.geometry.id
        ? "region selected" : "region on another display selected"
    case nil:
      return "draw a region or choose a target"
    }
  }

  private func regionOutline(_ region: CGRect) -> some View {
    ZStack(alignment: .topLeading) {
      Rectangle()
        .strokeBorder(.white, lineWidth: 2)
        .background(Color.white.opacity(0.06))
        .contentShape(Rectangle())

      ForEach(OverlayCorner.allCases, id: \.self) { corner in
        Circle()
          .fill(.white)
          .frame(width: 12, height: 12)
          .overlay(Circle().strokeBorder(.black, lineWidth: 1))
          .position(corner.position(in: region.size))
          .contentShape(Rectangle())

          .accessibilityLabel("resize region from \(corner.label) corner")
      }
    }
    .frame(width: region.width, height: region.height)
    .position(x: region.midX, y: region.midY)
    .accessibilityLabel("selected region")
    .accessibilityValue(
      "\(Int(region.width)) by \(Int(region.height)) points"
    )
  }

  private var regionGesture: some Gesture {
    DragGesture(minimumDistance: 2, coordinateSpace: .local)
      .onChanged { value in
        if dragIntent == nil {
          dragStart = clamped(value.startLocation)
          dragIntent = RegionDragIntent.at(
            value.startLocation, region: selectedRegion?.regionInDisplayPoints)
        }
        updateDrag(value, commit: false)
      }
      .onEnded { value in
        updateDrag(value, commit: true)
        draftRegion = nil
        dragStart = nil
        dragIntent = nil
        magnifierPoint = nil
      }
  }

  private func updateDrag(_ value: DragGesture.Value, commit: Bool) {
    guard let intent = dragIntent, let start = dragStart else { return }
    let current = clamped(value.location)
    var result: SelectionGeometry?
    switch intent {
    case .create:
      let rectangle = normalizedRegion(from: start, to: current)
      if rectangle.width >= 2, rectangle.height >= 2 {
        result = SelectionGeometry(display: screen.geometry, regionInDisplayPoints: rectangle)
      }
      magnifierPoint = current
    case .move:
      if let region = selectedRegion {
        let original = region.regionInDisplayPoints
        result = region.moved(
          to: CGPoint(
            x: original.minX + value.translation.width, y: original.minY + value.translation.height)
        )
      }
      magnifierPoint = nil
    case .resize(let corner):
      if let region = selectedRegion {
        let origin = corner.position(in: region.regionInDisplayPoints)
        let proposed = clamped(
          CGPoint(
            x: origin.x + value.translation.width, y: origin.y + value.translation.height))
        result = region.resized(dragging: corner.geometryCorner, to: proposed)
        if let result { magnifierPoint = corner.position(in: result.regionInDisplayPoints) }
      }
    }
    if commit {
      if let result { coordinator.selectRegion(result) }
    } else {
      draftRegion = result?.regionInDisplayPoints
    }
  }

  private func cornerMagnifier(at point: CGPoint) -> some View {
    let width = 120.0
    let x = min(max(point.x + 24, width / 2), displaySize.width - width / 2)
    let y = min(max(point.y + 24, width / 2), displaySize.height - width / 2)
    return ZStack {
      if let crop = screen.magnifierCrop(at: point) {
        Image(decorative: crop.image, scale: 1, orientation: .up)
          .interpolation(.none)
          .resizable()
          .frame(width: width, height: width)
        Rectangle().fill(.white.opacity(0.8))
          .frame(width: 1, height: width)
          .offset(x: (crop.focus.x / CGFloat(crop.image.width) - 0.5) * width)
        Rectangle().fill(.white.opacity(0.8))
          .frame(width: width, height: 1)
          .offset(y: (crop.focus.y / CGFloat(crop.image.height) - 0.5) * width)
      }
      Rectangle().strokeBorder(.white, lineWidth: 2)
    }
    .frame(width: width, height: width)
    .background(.black)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black, lineWidth: 1))
    .position(x: x, y: y)
    .accessibilityLabel("magnified capture edge")
  }

  private func normalizedRegion(from start: CGPoint, to end: CGPoint) -> CGRect {
    CGRect(
      x: min(start.x, end.x),
      y: min(start.y, end.y),
      width: abs(end.x - start.x),
      height: abs(end.y - start.y)
    )
  }

  private func clamped(_ point: CGPoint) -> CGPoint {
    CGPoint(
      x: min(max(point.x, 0), displaySize.width),
      y: min(max(point.y, 0), displaySize.height)
    )
  }
}

enum RegionDragIntent {
  case create, move
  case resize(OverlayCorner)

  static func at(_ point: CGPoint, region: CGRect?) -> RegionDragIntent {
    guard let region else { return .create }
    for corner in OverlayCorner.allCases {
      let position = corner.position(in: region)
      if abs(point.x - position.x) <= 12 && abs(point.y - position.y) <= 12 {
        return .resize(corner)
      }
    }
    return region.contains(point) ? .move : .create
  }
}

enum OverlayCorner: CaseIterable {
  case topLeft, topRight, bottomLeft, bottomRight

  var label: String {
    switch self {
    case .topLeft: "top left"
    case .topRight: "top right"
    case .bottomLeft: "bottom left"
    case .bottomRight: "bottom right"
    }
  }

  var geometryCorner: ResizeCorner {
    switch self {
    case .topLeft: .topLeft
    case .topRight: .topRight
    case .bottomLeft: .bottomLeft
    case .bottomRight: .bottomRight
    }
  }

  func position(in rect: CGRect) -> CGPoint {
    switch self {
    case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
    case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
    case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
    case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
    }
  }

  func position(in size: CGSize) -> CGPoint {
    position(in: CGRect(origin: .zero, size: size))
  }
}

extension SelectionScreen {
  func magnifierCrop(at point: CGPoint) -> SelectionMagnifierCrop? {
    let scaleX = CGFloat(snapshot.width) / geometry.localBounds.width
    let scaleY = CGFloat(snapshot.height) / geometry.localBounds.height
    let side = min(21, snapshot.width, snapshot.height)
    let x = min(max(Int(point.x * scaleX) - side / 2, 0), snapshot.width - side)
    let y = min(max(Int(point.y * scaleY) - side / 2, 0), snapshot.height - side)
    guard
      let image = snapshot.cropping(
        to: CGRect(x: x, y: y, width: side, height: side)
      )
    else { return nil }
    return SelectionMagnifierCrop(
      image: image,
      focus: CGPoint(
        x: min(max(point.x * scaleX - CGFloat(x), 0), CGFloat(side - 1)),
        y: min(max(point.y * scaleY - CGFloat(y), 0), CGFloat(side - 1))
      )
    )
  }
}

struct SelectionMagnifierCrop {
  let image: CGImage
  let focus: CGPoint
}
