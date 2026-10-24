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
  var frameRate = GIFCompressionFrameRate.fps24

  var isValid: Bool {
    (1...100).contains(qualityPercent)
  }
}

enum GIFCompressionFrameRate: Int, CaseIterable, Identifiable, Sendable {
  case fps24 = 24
  case fps18 = 18

  var id: Self { self }
  var framesPerSecond: Double { Double(rawValue) }
  var label: String { String(format: "%g", framesPerSecond) }
}

struct GIFSizeSearchCandidate: Equatable, Sendable {
  let scale: GIFCompressionScale
  let frameRate: GIFCompressionFrameRate
  let qualityPercent: Int

  var settings: GIFCompressionSettings {
    GIFCompressionSettings(
      scale: scale, qualityPercent: qualityPercent, frameRate: frameRate)
  }
}

struct GIFSizeSearchPlan: Sendable {
  let candidates: [GIFSizeSearchCandidate]

  init(
    settings: GIFCompressionSettings,
    frameRates: [GIFCompressionFrameRate] = [.fps24, .fps18],
    eligibleScales: [GIFCompressionScale]? = nil
  ) {
    let scales = (eligibleScales ?? [.original, .seventyFivePercent, .fiftyPercent])
      .filter { $0.rawValue <= settings.scale.rawValue }
      .sorted { $0.rawValue > $1.rawValue }
    let rates = Array(Set(frameRates)).sorted { $0.rawValue > $1.rawValue }
    let approvedPairs = Set(["100-24", "100-18", "75-24", "50-24"])
    let pairs = rates.flatMap { rate in
      scales.filter { approvedPairs.contains("\($0.rawValue)-\(rate.rawValue)") }
        .map { ($0, rate) }
    }
    var qualities = [max(90, settings.qualityPercent)]
    var nextQuality = qualities[0]
    while nextQuality > 90 {
      nextQuality = max(90, nextQuality - 5)
      qualities.append(nextQuality)
    }
    candidates = pairs.flatMap { scale, rate in
      qualities.map { quality in
        GIFSizeSearchCandidate(scale: scale, frameRate: rate, qualityPercent: quality)
      }
    }
  }
}

struct GIFFrameSample: Equatable, Sendable {
  let sourceIndices: [Int]
  let outputTimestamps: [TimeInterval]
  let expectedDelaysCentiseconds: [Int]
  let durationCentiseconds: Int
}

enum GIFFrameSampler {
  static func sample(
    delaysCentiseconds: [Int], frameRate: GIFCompressionFrameRate
  ) throws -> GIFFrameSample {
    guard !delaysCentiseconds.isEmpty, delaysCentiseconds.allSatisfy({ $0 > 0 }) else {
      throw GifskiCompressionError.invalidSource
    }
    var sourceBoundaries: [Int] = []
    var total = 0
    for delay in delaysCentiseconds {
      sourceBoundaries.append(total)
      let (next, overflow) = total.addingReportingOverflow(delay)
      guard !overflow else { throw GifskiCompressionError.invalidSource }
      total = next
    }
    let rate = frameRate.framesPerSecond
    let frameCount = max(1, Int(floor(Double(total) * rate / 100)))
    guard frameCount > 0, frameCount < 1_000_000 else {
      throw GifskiCompressionError.unrepresentableTiming
    }
    var indices: [Int] = []
    var timestamps: [TimeInterval] = []
    for frame in 0..<frameCount {
      let time = Double(frame) / rate
      let centiseconds = time * 100
      let index = sourceBoundaries.lastIndex(where: { Double($0) <= centiseconds }) ?? 0
      indices.append(index)
      timestamps.append(time)
    }
    var boundaries = timestamps.dropFirst().map {
      Int(($0 * 100).rounded(.toNearestOrAwayFromZero))
    }
    boundaries.insert(0, at: 0)
    boundaries.append(total)
    let delays = zip(boundaries, boundaries.dropFirst()).map { $1 - $0 }
    guard delays.allSatisfy({ $0 > 0 }), total <= 65_535 else {
      throw GifskiCompressionError.unrepresentableTiming
    }
    return GIFFrameSample(
      sourceIndices: indices,
      outputTimestamps: timestamps,
      expectedDelaysCentiseconds: delays,
      durationCentiseconds: total
    )
  }
}

enum GIFFrameScheduleValidator {
  static func finalFrameDelay(
    emittedDelaysCentiseconds: [Int], expectedDelaysCentiseconds: [Int]
  ) -> Int? {
    guard !emittedDelaysCentiseconds.isEmpty,
      emittedDelaysCentiseconds.allSatisfy({ $0 > 0 }),
      !expectedDelaysCentiseconds.isEmpty,
      expectedDelaysCentiseconds.allSatisfy({ $0 > 0 })
    else { return nil }

    var expectedIndex = 0
    for emittedDelay in emittedDelaysCentiseconds.dropLast() {
      var mergedDelay = 0
      while expectedIndex < expectedDelaysCentiseconds.count, mergedDelay < emittedDelay {
        mergedDelay += expectedDelaysCentiseconds[expectedIndex]
        expectedIndex += 1
      }
      guard mergedDelay == emittedDelay else { return nil }
    }
    guard expectedIndex < expectedDelaysCentiseconds.count else { return nil }
    let remainingDelay = expectedDelaysCentiseconds[expectedIndex...].reduce(0, +)
    return remainingDelay > 0 ? remainingDelay : nil
  }

  static func matches(
    emittedDelaysCentiseconds: [Int], expectedDelaysCentiseconds: [Int]
  ) -> Bool {
    guard !emittedDelaysCentiseconds.isEmpty,
      !expectedDelaysCentiseconds.isEmpty,
      emittedDelaysCentiseconds.allSatisfy({ $0 > 0 }),
      expectedDelaysCentiseconds.allSatisfy({ $0 > 0 })
    else { return false }

    var expectedIndex = 0
    for emittedDelay in emittedDelaysCentiseconds {
      var mergedDelay = 0
      while expectedIndex < expectedDelaysCentiseconds.count, mergedDelay < emittedDelay {
        mergedDelay += expectedDelaysCentiseconds[expectedIndex]
        expectedIndex += 1
      }
      guard mergedDelay == emittedDelay else { return false }
    }
    return expectedIndex == expectedDelaysCentiseconds.count
  }
}

struct GIFSizeSearchResult: Sendable {
  let gif: EncodedGIF
  let settings: GIFCompressionSettings
  let reachedTarget: Bool
  let attempts: Int
}

struct GIFSizeSearchProgress: Equatable, Sendable {
  let attempt: Int
  let totalAttempts: Int
  let settings: GIFCompressionSettings
}

struct GIFSizeSearchSummary: Equatable, Sendable {
  let fileBytes: Int64
  let targetBytes: Int64
  let settings: GIFCompressionSettings
  let reachedTarget: Bool
  let attempts: Int
}

enum GIFSizeSearchEngine {
  @MainActor
  static func search(
    source: EncodedGIF,
    settings: GIFCompressionSettings,
    plan: GIFSizeSearchPlan,
    compress: (GIFCompressionSettings) async throws -> EncodedGIF,
    discard: (EncodedGIF) async -> Void,
    onProgress: @Sendable (Int, Int, GIFCompressionSettings) async -> Void = { _, _, _ in }
  ) async throws -> GIFSizeSearchResult {
    guard !plan.candidates.isEmpty else { throw GifskiCompressionError.unrepresentableTiming }
    var best: (EncodedGIF, GIFCompressionSettings)?
    do {
      for (offset, candidate) in plan.candidates.enumerated() {
        try Task.checkCancellation()
        await onProgress(offset + 1, plan.candidates.count, candidate.settings)
        let output = try await compress(candidate.settings)
        do {
          try Task.checkCancellation()
        } catch {
          await discard(output)
          throw error
        }
        guard output.durationCentiseconds == source.durationCentiseconds,
          output.loopsForever == source.loopsForever
        else {
          await discard(output)
          throw GifskiCompressionError.invalidOutput
        }
        if best == nil || output.fileBytes < best!.0.fileBytes {
          if let prior = best { await discard(prior.0) }
          best = (output, candidate.settings)
        } else {
          await discard(output)
        }
      }
    } catch {
      if let best { await discard(best.0) }
      throw error
    }
    guard let best else { throw GifskiCompressionError.invalidOutput }
    return GIFSizeSearchResult(
      gif: best.0, settings: best.1,
      reachedTarget: best.0.fileBytes <= settings.destination.targetBytes,
      attempts: plan.candidates.count)
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
    compressed.frameCount > 0,
    compressed.delaysCentiseconds.count == compressed.frameCount,
    let sample = try? GIFFrameSampler.sample(
      delaysCentiseconds: source.delaysCentiseconds, frameRate: settings.frameRate),
    GIFFrameScheduleValidator.matches(
      emittedDelaysCentiseconds: compressed.delaysCentiseconds,
      expectedDelaysCentiseconds: sample.expectedDelaysCentiseconds),
    abs(compressed.width - settings.scale.expectedDimension(source.width)) <= 1,
    abs(compressed.height - settings.scale.expectedDimension(source.height)) <= 1,
    compressed.durationCentiseconds == source.durationCentiseconds,
    compressed.loopsForever == source.loopsForever,
    compressed.fileBytes > 0,
    compressed.fileBytes <= reservation.maximumBytes
  else { throw OriginalGIFEncodingError.invalidOutput }
  let actual = try GIFMetadataInspector().inspect(compressed.url)
  guard actual == compressed else { throw OriginalGIFEncodingError.invalidOutput }
}
