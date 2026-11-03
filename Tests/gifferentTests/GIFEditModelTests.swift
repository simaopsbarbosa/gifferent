import Foundation
import XCTest

@testable import gifferent

final class GIFEditModelTests: XCTestCase {
  func testTrimTimelineUsesSourceTimestampsAndTerminalDuration() {
    let source = CapturedPNGSequence(
      frames: [10.0, 10.25, 11.0].map {
        CapturedPNGFrame(url: URL(fileURLWithPath: "/tmp/frame"), timestamp: $0)
      },
      finalFrameDuration: 1)
    let boundaries = GIFTrimTimeline.boundaries(for: source)
    XCTAssertEqual(boundaries.count, 4)
    XCTAssertEqual(boundaries[0], 0, accuracy: 1e-12)
    XCTAssertEqual(boundaries[1], 0.125, accuracy: 1e-12)
    XCTAssertEqual(boundaries[2], 0.5, accuracy: 1e-12)
    XCTAssertEqual(boundaries[3], 1, accuracy: 1e-12)
  }

  func testTrimTimelineSnapsToFrameBoundaryAndRespectsHandleLimits() {
    let boundaries = [0.0, 0.125, 0.5, 1.0]
    XCTAssertEqual(
      GIFTrimTimeline.nearestBoundary(to: 0.4, boundaries: boundaries, lower: 0, upper: 3), 2)
    XCTAssertEqual(
      GIFTrimTimeline.nearestBoundary(to: -1, boundaries: boundaries, lower: 1, upper: 3), 1)
    XCTAssertEqual(
      GIFTrimTimeline.nearestBoundary(to: 2, boundaries: boundaries, lower: 0, upper: 2), 2)
  }

  func testTrimTimelineSingleFrameHasTwoUsableBoundaries() {
    let source = sequence(timestamps: [42])
    let boundaries = GIFTrimTimeline.boundaries(for: source)
    XCTAssertEqual(boundaries, [0, 1])
    XCTAssertEqual(
      GIFTrimTimeline.nearestBoundary(to: 0.9, boundaries: boundaries, lower: 0, upper: 0), 0)
    XCTAssertEqual(
      GIFTrimTimeline.nearestBoundary(to: 0.1, boundaries: boundaries, lower: 1, upper: 1), 1)
  }

  func testTrimsHalfOpenFrameRangeAndNormalizesSpeedAdjustedTimestamps() throws {
    let source = sequence(timestamps: [10, 10.1, 10.5, 10.75])
    let result = try GIFEditModel.apply(
      GIFEditParameters(
        frameRange: GIFFrameRange(startIndex: 1, endIndexExclusive: 4),
        playbackSpeed: 2,
        loopMode: .forever
      ),
      to: source
    )

    XCTAssertEqual(result.sequence.frames.map(\.url), source.frames[1..<4].map(\.url))
    XCTAssertEqual(result.sequence.frames[0].timestamp, 0, accuracy: 1e-12)
    XCTAssertEqual(result.sequence.frames[1].timestamp, 0.2, accuracy: 1e-12)
    XCTAssertEqual(result.sequence.frames[2].timestamp, 0.34, accuracy: 1e-12)
    XCTAssertTrue(
      zip(result.sequence.frames, result.sequence.frames.dropFirst()).allSatisfy { pair in
        pair.0.timestamp < pair.1.timestamp
      })
    XCTAssertEqual(result.loopMode, .forever)
  }

  func testKeepsFullRangeAtNormalSpeedAndCarriesOnceMode() throws {
    let source = sequence(timestamps: [3, 3.25, 4])
    let result = try GIFEditModel.apply(
      GIFEditParameters(
        frameRange: GIFFrameRange(startIndex: 0, endIndexExclusive: source.frames.count),
        playbackSpeed: 1,
        loopMode: .once
      ),
      to: source
    )

    XCTAssertEqual(result.sequence.frames.map(\.timestamp), [0, 0.26, 1])
    XCTAssertEqual(result.loopMode, .once)
  }

  func testSingleFrameProducesZeroOriginTimestamp() throws {
    let source = sequence(timestamps: [42])
    let result = try GIFEditModel.apply(
      GIFEditParameters(
        frameRange: GIFFrameRange(startIndex: 0, endIndexExclusive: 1),
        playbackSpeed: 0.5,
        loopMode: .once
      ),
      to: source
    )

    XCTAssertEqual(result.sequence.frames.map(\.timestamp), [0])
    XCTAssertEqual(result.sequence.finalFrameDuration, 0.03)
  }

  func testRejectsEmptySequenceAndInvalidRanges() {
    XCTAssertThrowsError(
      try GIFEditModel.apply(parameters(range: 0..<0), to: CapturedPNGSequence(frames: []))
    ) { XCTAssertEqual($0 as? GIFEditModelError, .emptySequence) }

    let source = sequence(timestamps: [0, 1, 2])
    for range in [
      GIFFrameRange(startIndex: -1, endIndexExclusive: 1),
      GIFFrameRange(startIndex: 0, endIndexExclusive: 4),
      GIFFrameRange(startIndex: 2, endIndexExclusive: 2),
      GIFFrameRange(startIndex: 3, endIndexExclusive: 2),
    ] {
      XCTAssertThrowsError(
        try GIFEditModel.apply(
          GIFEditParameters(frameRange: range, playbackSpeed: 1, loopMode: .forever),
          to: source
        )
      ) { XCTAssertEqual($0 as? GIFEditModelError, .invalidFrameRange) }
    }
  }

  func testRejectsNonpositiveOrNonfinitePlaybackSpeed() {
    let source = sequence(timestamps: [0, 1])
    let speeds: [Double] = [0, -1, Double.infinity, -Double.infinity, Double.nan]
    for speed in speeds {
      XCTAssertThrowsError(
        try GIFEditModel.apply(
          GIFEditParameters(
            frameRange: GIFFrameRange(startIndex: 0, endIndexExclusive: 2),
            playbackSpeed: speed,
            loopMode: .forever
          ),
          to: source
        )
      ) { XCTAssertEqual($0 as? GIFEditModelError, .invalidPlaybackSpeed) }
    }
  }

  func testRejectsInvalidSelectedTimestamps() {
    let invalidSequences = [
      sequence(timestamps: [0, 1, 1]),
      sequence(timestamps: [0, 2, 1]),
      sequence(timestamps: [0, .infinity, 2]),
      sequence(timestamps: [0, .nan, 2]),
    ]
    for source in invalidSequences {
      XCTAssertThrowsError(
        try GIFEditModel.apply(
          GIFEditParameters(
            frameRange: GIFFrameRange(startIndex: 0, endIndexExclusive: source.frames.count),
            playbackSpeed: 1,
            loopMode: .forever
          ),
          to: source
        )
      ) { XCTAssertEqual($0 as? GIFEditModelError, .invalidTimestamps) }
    }
  }

  func testRejectsTimingThatCannotRemainStrictlyIncreasing() {
    let source = sequence(timestamps: [0, 1e-300, 2e-300])
    XCTAssertThrowsError(
      try GIFEditModel.apply(
        GIFEditParameters(
          frameRange: GIFFrameRange(startIndex: 0, endIndexExclusive: 3),
          playbackSpeed: 1e300,
          loopMode: .forever
        ),
        to: source
      )
    ) { XCTAssertEqual($0 as? GIFEditModelError, .unrepresentableTiming) }
  }

  func testInvalidTimestampsOutsideTrimmedRangeDoNotAffectSelection() throws {
    let source = sequence(timestamps: [.nan, 4, 5])
    let result = try GIFEditModel.apply(
      GIFEditParameters(
        frameRange: GIFFrameRange(startIndex: 1, endIndexExclusive: 3),
        playbackSpeed: 1,
        loopMode: .forever
      ),
      to: source
    )

    XCTAssertEqual(result.sequence.frames.map(\.timestamp), [0, 1])
  }

  func testAllExportPresetsAfterSpeedHaveBoundedDelaysAndExactDuration() throws {
    let source = CapturedPNGSequence(
      frames: (0..<120).map { index in
        CapturedPNGFrame(
          url: URL(fileURLWithPath: "/tmp/\(index).png"), timestamp: Double(index) / 60)
      }, finalFrameDuration: 1.0 / 60)
    for speed in GIFEditParameters.speedPresets {
      for rate in GIFCompressionFrameRate.exportPresets {
        let edited = try GIFEditModel.apply(
          GIFEditParameters(
            frameRange: GIFFrameRange(startIndex: 0, endIndexExclusive: 120),
            playbackSpeed: speed, loopMode: .once, frameRate: rate), to: source)
        let delays = try ImageIOOriginalGIFEncoder.frameDelaysCentiseconds(
          for: edited.sequence.frames.map(\.timestamp),
          finalFrameDuration: edited.sequence.finalFrameDuration)
        XCTAssertEqual(delays.reduce(0, +), Int((200 / speed).rounded()))
        XCTAssertTrue(delays.allSatisfy { $0 >= 2 })
        XCTAssertLessThanOrEqual(edited.sequence.frames.count, 120)
        let indices = edited.sequence.frames.map {
          Int($0.url.deletingPathExtension().lastPathComponent)!
        }
        XCTAssertTrue(zip(indices, indices.dropFirst()).allSatisfy { $0 < $1 })
        XCTAssertEqual(edited.loopMode, .once)
      }
    }
  }

  func testFPSIsAppliedAfterSpeedAndSparseFramesAreHeld() throws {
    let source = CapturedPNGSequence(
      frames: (0..<120).map { index in
        CapturedPNGFrame(
          url: URL(fileURLWithPath: "/tmp/\(index).png"), timestamp: Double(index) / 60)
      }, finalFrameDuration: 1.0 / 60)
    for speed in [1.0, 2.0] {
      let output = try GIFEditModel.apply(
        GIFEditParameters(
          frameRange: GIFFrameRange(startIndex: 0, endIndexExclusive: 120),
          playbackSpeed: speed, loopMode: .forever, frameRate: .fps24), to: source
      ).sequence
      XCTAssertEqual(output.frames.count, Int(48 / speed))
    }
    let sparse = CapturedPNGSequence(
      frames: source.frames.filter { $0.timestamp == 0 || $0.timestamp == 1 },
      finalFrameDuration: 1)
    let output = try GIFEditModel.apply(
      GIFEditParameters(
        frameRange: GIFFrameRange(startIndex: 0, endIndexExclusive: 2),
        playbackSpeed: 1, loopMode: .forever), to: sparse
    ).sequence
    XCTAssertEqual(output.frames.map(\.timestamp), [0, 1])
    XCTAssertEqual(output.frames.map(\.url), sparse.frames.map(\.url))
    XCTAssertEqual(output.finalFrameDuration, 1)
  }

  func testVeryShortTrimRetainsOneBrowserCompatibleFrame() throws {
    let output = try GIFEditModel.apply(
      GIFEditParameters(
        frameRange: GIFFrameRange(startIndex: 0, endIndexExclusive: 1),
        playbackSpeed: 3, loopMode: .once),
      to: CapturedPNGSequence(
        frames: [CapturedPNGFrame(url: URL(fileURLWithPath: "/tmp/one.png"), timestamp: 0)],
        finalFrameDuration: 1.0 / 60)
    ).sequence
    XCTAssertEqual(output.frames.count, 1)
    XCTAssertEqual(output.finalFrameDuration, 0.02)
  }

  private func parameters(range: Range<Int>) -> GIFEditParameters {
    GIFEditParameters(
      frameRange: GIFFrameRange(startIndex: range.lowerBound, endIndexExclusive: range.upperBound),
      playbackSpeed: 1,
      loopMode: .forever
    )
  }

  private func sequence(timestamps: [TimeInterval]) -> CapturedPNGSequence {
    CapturedPNGSequence(
      frames: timestamps.enumerated().map { index, timestamp in
        CapturedPNGFrame(url: URL(fileURLWithPath: "/tmp/frame-\(index).png"), timestamp: timestamp)
      }
    )
  }
}
