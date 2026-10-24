import Foundation

struct RecordingFrame: Sendable, Equatable {
  let timestampNanoseconds: Int64
  let width: Int
  let height: Int
  let bytesPerRow: Int
  let bgra: Data
}

struct RecordingFrameStatistics: Sendable, Equatable {
  /// valid, increasing frames offered to the bounded stream, including those later displaced.
  let accepted: Int
  /// accepted frames displaced from the newest-frame buffer before consumption.
  let dropped: Int
  /// frames rejected because their timestamp was negative, repeated, or moved backward.
  let rejectedTimestamps: Int
}

/// local, in-memory measurements for one recording; these values are not persisted or uploaded.
struct RecordingDiagnostics: Sendable, Equatable {
  var frameStatistics = RecordingFrameStatistics(accepted: 0, dropped: 0, rejectedTimestamps: 0)
  var startToRecording: Duration?
  var stopToCapturedSession: Duration?
  var stopToPreviewReady: Duration?
}

@MainActor
protocol RecordingDiagnosticsClock {
  /// seconds on a monotonic timeline with an arbitrary origin.
  func now() -> Duration
}

@MainActor
struct SystemRecordingDiagnosticsClock: RecordingDiagnosticsClock {
  private let clock = ContinuousClock()
  private let origin = ContinuousClock().now

  func now() -> Duration {
    origin.duration(to: clock.now)
  }
}

/// a bounded handoff from the screen callback to a frame consumer.
final class RecordingFrameTransport: @unchecked Sendable {
  let frames: AsyncStream<RecordingFrame>

  private let lock = NSLock()
  private let continuation: AsyncStream<RecordingFrame>.Continuation
  private var accepted = 0
  private var dropped = 0
  private var rejectedTimestamps = 0
  private var lastTimestamp: Int64?
  private var finished = false

  init(capacity: Int = 3) {
    precondition(capacity > 0)
    let pair = AsyncStream.makeStream(
      of: RecordingFrame.self,
      bufferingPolicy: .bufferingNewest(capacity)
    )
    frames = pair.stream
    continuation = pair.continuation
  }

  func offer(_ frame: RecordingFrame) {
    lock.lock()
    defer { lock.unlock() }
    guard !finished else { return }
    guard frame.timestampNanoseconds >= 0,
      lastTimestamp.map({ frame.timestampNanoseconds > $0 }) ?? true
    else {
      rejectedTimestamps += 1
      return
    }

    switch continuation.yield(frame) {
    case .enqueued:
      accepted += 1
      lastTimestamp = frame.timestampNanoseconds
    case .dropped:
      accepted += 1
      dropped += 1
      lastTimestamp = frame.timestampNanoseconds
    case .terminated:
      finished = true
    @unknown default:
      finished = true
    }
  }

  func finish() {
    lock.lock()
    finished = true
    continuation.finish()
    lock.unlock()
  }

  func statistics() -> RecordingFrameStatistics {
    lock.lock()
    defer { lock.unlock() }
    return RecordingFrameStatistics(
      accepted: accepted,
      dropped: dropped,
      rejectedTimestamps: rejectedTimestamps
    )
  }
}
