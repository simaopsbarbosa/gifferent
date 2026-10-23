import Foundation
import XCTest

@testable import gifferent

final class RecordingFrameTransportTests: XCTestCase {
  func testNewestFramesSurviveWhenConsumerFallsBehind() async {
    let transport = RecordingFrameTransport(capacity: 2)
    transport.offer(frame(at: 1))
    transport.offer(frame(at: 2))
    transport.offer(frame(at: 3))
    transport.finish()

    var timestamps: [Int64] = []
    for await frame in transport.frames {
      timestamps.append(frame.timestampNanoseconds)
    }

    XCTAssertEqual(timestamps, [2, 3])
    XCTAssertEqual(
      transport.statistics(),
      RecordingFrameStatistics(accepted: 3, dropped: 1, rejectedTimestamps: 0)
    )
  }

  func testDuplicateAndBackwardTimestampsAreRejected() async {
    let transport = RecordingFrameTransport(capacity: 3)
    transport.offer(frame(at: 10))
    transport.offer(frame(at: 10))
    transport.offer(frame(at: 9))
    transport.offer(frame(at: -1))
    transport.offer(frame(at: 11))
    transport.finish()

    var timestamps: [Int64] = []
    for await frame in transport.frames {
      timestamps.append(frame.timestampNanoseconds)
    }

    XCTAssertEqual(timestamps, [10, 11])
    XCTAssertEqual(
      transport.statistics(),
      RecordingFrameStatistics(accepted: 2, dropped: 0, rejectedTimestamps: 3)
    )
  }

  private func frame(at time: Int64) -> RecordingFrame {
    RecordingFrame(
      timestampNanoseconds: time,
      width: 1,
      height: 1,
      bytesPerRow: 4,
      bgra: Data([0, 0, 0, 255])
    )
  }
}
