import CoreGraphics

struct DisplayGeometry: Equatable {
  let id: UInt32
  let frameInGlobalPoints: CGRect
  let pixelWidth: Int
  let pixelHeight: Int

  init?(id: UInt32, frameInGlobalPoints: CGRect, pixelWidth: Int, pixelHeight: Int) {
    guard frameInGlobalPoints.isFiniteAndPositive,
      pixelWidth > 0,
      pixelHeight > 0
    else { return nil }

    self.id = id
    self.frameInGlobalPoints = frameInGlobalPoints
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
  }

  var localBounds: CGRect {
    CGRect(origin: .zero, size: frameInGlobalPoints.size)
  }
}

struct CapturePixelRegion: Equatable {
  let x: Int
  let y: Int
  let width: Int
  let height: Int
}

enum ResizeCorner {
  case topLeft
  case topRight
  case bottomLeft
  case bottomRight
}

/// the region uses display-local points with a top-left origin.
struct SelectionGeometry: Equatable {
  let display: DisplayGeometry
  let regionInDisplayPoints: CGRect

  init?(display: DisplayGeometry, regionInDisplayPoints: CGRect) {
    guard regionInDisplayPoints.isFiniteAndPositive,
      regionInDisplayPoints.minX >= 0,
      regionInDisplayPoints.minY >= 0,
      regionInDisplayPoints.maxX <= display.localBounds.width,
      regionInDisplayPoints.maxY <= display.localBounds.height
    else { return nil }

    self.display = display
    self.regionInDisplayPoints = regionInDisplayPoints
  }

  func isValid(on currentDisplay: DisplayGeometry) -> Bool {
    display == currentDisplay
  }

  func moved(to proposedOrigin: CGPoint) -> SelectionGeometry? {
    guard proposedOrigin.x.isFinite, proposedOrigin.y.isFinite else { return nil }

    let origin = CGPoint(
      x: proposedOrigin.x.clamped(
        to: 0...(display.localBounds.width - regionInDisplayPoints.width)),
      y: proposedOrigin.y.clamped(
        to: 0...(display.localBounds.height - regionInDisplayPoints.height))
    )
    return SelectionGeometry(
      display: display,
      regionInDisplayPoints: CGRect(origin: origin, size: regionInDisplayPoints.size)
    )
  }

  /// resizing keeps the top-left corner fixed and clamps the far edges to the display.
  func resized(to proposedSize: CGSize) -> SelectionGeometry? {
    guard proposedSize.width.isFinite,
      proposedSize.height.isFinite,
      proposedSize.width > 0,
      proposedSize.height > 0
    else { return nil }

    let size = CGSize(
      width: min(proposedSize.width, display.localBounds.width - regionInDisplayPoints.minX),
      height: min(proposedSize.height, display.localBounds.height - regionInDisplayPoints.minY)
    )
    return SelectionGeometry(
      display: display,
      regionInDisplayPoints: CGRect(origin: regionInDisplayPoints.origin, size: size)
    )
  }

  /// the opposite corner stays fixed; a corner cannot cross it.
  func resized(dragging corner: ResizeCorner, to proposedPoint: CGPoint) -> SelectionGeometry? {
    guard proposedPoint.x.isFinite, proposedPoint.y.isFinite else { return nil }

    let minimumWidth = min(
      display.localBounds.width / CGFloat(display.pixelWidth), regionInDisplayPoints.width)
    let minimumHeight = min(
      display.localBounds.height / CGFloat(display.pixelHeight), regionInDisplayPoints.height)

    let left: CGFloat
    let right: CGFloat
    let top: CGFloat
    let bottom: CGFloat

    switch corner {
    case .topLeft:
      right = regionInDisplayPoints.maxX
      bottom = regionInDisplayPoints.maxY
      left = proposedPoint.x.clamped(to: 0...(right - minimumWidth))
      top = proposedPoint.y.clamped(to: 0...(bottom - minimumHeight))
    case .topRight:
      left = regionInDisplayPoints.minX
      bottom = regionInDisplayPoints.maxY
      right = proposedPoint.x.clamped(to: (left + minimumWidth)...display.localBounds.width)
      top = proposedPoint.y.clamped(to: 0...(bottom - minimumHeight))
    case .bottomLeft:
      right = regionInDisplayPoints.maxX
      top = regionInDisplayPoints.minY
      left = proposedPoint.x.clamped(to: 0...(right - minimumWidth))
      bottom = proposedPoint.y.clamped(to: (top + minimumHeight)...display.localBounds.height)
    case .bottomRight:
      left = regionInDisplayPoints.minX
      top = regionInDisplayPoints.minY
      right = proposedPoint.x.clamped(to: (left + minimumWidth)...display.localBounds.width)
      bottom = proposedPoint.y.clamped(to: (top + minimumHeight)...display.localBounds.height)
    }

    return SelectionGeometry(
      display: display,
      regionInDisplayPoints: CGRect(x: left, y: top, width: right - left, height: bottom - top)
    )
  }

  func capturePixels(on currentDisplay: DisplayGeometry) -> CapturePixelRegion? {
    guard isValid(on: currentDisplay) else { return nil }

    let scaleX = CGFloat(display.pixelWidth) / display.localBounds.width
    let scaleY = CGFloat(display.pixelHeight) / display.localBounds.height
    let minX = Int(floor(regionInDisplayPoints.minX * scaleX))
    let minY = Int(floor(regionInDisplayPoints.minY * scaleY))
    let maxX = min(Int(ceil(regionInDisplayPoints.maxX * scaleX)), display.pixelWidth)
    let maxY = min(Int(ceil(regionInDisplayPoints.maxY * scaleY)), display.pixelHeight)
    return CapturePixelRegion(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }
}

extension CGRect {
  fileprivate var isFiniteAndPositive: Bool {
    origin.x.isFinite && origin.y.isFinite && width.isFinite && height.isFinite && width > 0
      && height > 0
  }
}

extension CGFloat {
  fileprivate func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}
