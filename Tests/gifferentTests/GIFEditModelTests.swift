import Foundation
import XCTest

@testable import gifferent

final class GIFEditModelTests: XCTestCase {
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
    XCTAssertEqual(result.sequence.frames[1].timestamp, 0.1, accuracy: 1e-12)
    XCTAssertEqual(result.sequence.frames[2].timestamp, 0.325, accuracy: 1e-12)
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

    XCTAssertEqual(result.sequence.frames.map(\.timestamp), [0, 0.25, 1])
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
    for speed in [0, -1, .infinity, -.infinity, .nan] {
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
