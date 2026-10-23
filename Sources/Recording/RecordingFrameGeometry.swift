import CoreGraphics

enum RecordingFrameGeometry {
  static let outsideInset: CGFloat = 4
  static let labelHeight: CGFloat = 18

  static func regionFrame(
    _ regionInDisplayPoints: CGRect,
    displayFrame: CGRect
  ) -> CGRect? {
    guard regionInDisplayPoints.isFiniteAndPositive,
      displayFrame.isFiniteAndPositive,
      CGRect(origin: .zero, size: displayFrame.size).contains(regionInDisplayPoints)
    else { return nil }

    return CGRect(
      x: displayFrame.minX + regionInDisplayPoints.minX,
      y: displayFrame.minY + displayFrame.height - regionInDisplayPoints.maxY,
      width: regionInDisplayPoints.width,
      height: regionInDisplayPoints.height
    )
  }

  static func panelFrame(around targetFrame: CGRect) -> CGRect? {
    guard targetFrame.isFiniteAndPositive else { return nil }
    return CGRect(
      x: targetFrame.minX - outsideInset,
      y: targetFrame.minY - outsideInset,
      width: targetFrame.width + outsideInset * 2,
      height: targetFrame.height + outsideInset * 2 + labelHeight
    )
  }

  static func targetRect(inPanelFor targetFrame: CGRect) -> CGRect? {
    guard panelFrame(around: targetFrame) != nil else { return nil }
    return CGRect(
      x: outsideInset,
      y: labelHeight,
      width: targetFrame.width,
      height: targetFrame.height
    )
  }
}

extension CGRect {
  fileprivate var isFiniteAndPositive: Bool {
    origin.x.isFinite && origin.y.isFinite && width.isFinite && height.isFinite && width > 0
      && height > 0
  }
}
