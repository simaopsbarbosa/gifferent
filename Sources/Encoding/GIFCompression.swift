import Foundation

enum GIFCompressionDestination: CaseIterable, Identifiable, Sendable {
  case github
  case discord

  var id: Self { self }

  var displayName: String {
    switch self {
    case .github: "GitHub"
    case .discord: "Discord"
    }
  }

  var systemImage: String {
    switch self {
    case .github: "chevron.left.forwardslash.chevron.right"
    case .discord: "bubble.left.and.bubble.right"
    }
  }

  var targetBytes: Int64 {
    switch self {
    case .github: 9_000_000
    case .discord: 18_000_000
    }
  }

  var publishedMaximumBytes: Int64 {
    switch self {
    case .github: 10_000_000
    case .discord: 20_000_000
    }
  }

  var targetLabel: String {
    switch self {
    case .github: "9 MB"
    case .discord: "18 MB"
    }
  }

  var buttonTitle: String {
    let target = "\(targetLabel) target"
    let maximum = "\(publishedMaximumLabel) max"
    return "\(displayName) · \(target) · \(maximum)"
  }

  var publishedMaximumLabel: String {
    switch self {
    case .github: "10 MB"
    case .discord: "20 MB"
    }
  }

  var limitScopeDescription: String {
    switch self {
    case .github: "issue, pull request, and comment image/GIF attachments"
    case .discord: "non-Nitro attachments; selected users may have higher limits"
    }
  }

  var limitResearchDate: String { "2026-10-24" }

  var accessibilityID: String {
    switch self {
    case .github: "github"
    case .discord: "discord"
    }
  }
}

enum GIFCompressionScale: Int, CaseIterable, Identifiable, Sendable {
  case original = 100
  case seventyFivePercent = 75
  case fiftyPercent = 50
  case twentyFivePercent = 25

  var id: Self { self }

  var label: String {
    self == .original ? "original" : "\(rawValue)%"
  }

  func expectedDimension(_ sourceDimension: Int) -> Int {
    guard self != .original else { return sourceDimension }
    return Int((Double(sourceDimension) * Double(rawValue) / 100).rounded(.toNearestOrAwayFromZero))
  }
}

struct GIFCompressionSettings: Equatable, Sendable {
  var destination: GIFCompressionDestination = .github
  var scale: GIFCompressionScale = .original
  var qualityPercent = 90

  var isValid: Bool {
    (1...100).contains(qualityPercent)
  }
}

enum GIFCompressionAction: Equatable {
  case unavailable
  case idle
  case compressing
  case compressed
  case failed
  case cancelled
}

protocol GIFCompressing: Sendable {
  /// writes a local replacement and returns its metadata.
  ///
  /// implementations must stop promptly on cancellation and keep output and cache use within
  /// the reservation limits while writing; the workspace validates and accounts the final files.
  func compress(
    source: EncodedGIF,
    settings: GIFCompressionSettings,
    to reservation: CompressedPreviewOutputReservation
  ) async throws -> EncodedGIF
}

func validateCompressedGIFOutput(
  _ compressed: EncodedGIF,
  source: EncodedGIF,
  settings: GIFCompressionSettings,
  reservation: CompressedPreviewOutputReservation
) throws {
  guard settings.isValid,
    compressed.url == reservation.url,
    compressed.frameCount == source.frameCount,
    abs(compressed.width - settings.scale.expectedDimension(source.width)) <= 1,
    abs(compressed.height - settings.scale.expectedDimension(source.height)) <= 1,
    compressed.delaysCentiseconds == source.delaysCentiseconds,
    compressed.durationCentiseconds == source.durationCentiseconds,
    compressed.loopsForever == source.loopsForever,
    compressed.fileBytes > 0,
    compressed.fileBytes <= reservation.maximumBytes
  else { throw OriginalGIFEncodingError.invalidOutput }
  let actual = try GIFMetadataInspector().inspect(compressed.url)
  guard actual == compressed else { throw OriginalGIFEncodingError.invalidOutput }
}
