import Foundation

enum GIFCompressionFrameRate: Int, CaseIterable, Identifiable, Sendable {
  case fps50 = 50
  case fps45 = 45
  case fps30 = 30
  case fps24 = 24
  case fps20 = 20
  case fps18 = 18
  case fps15 = 15
  case fps10 = 10

  static let exportPresets: [Self] = [.fps50, .fps45, .fps30, .fps24, .fps20, .fps15, .fps10]

  var id: Self { self }
  var framesPerSecond: Double { Double(rawValue) }
  var label: String { String(format: "%g", framesPerSecond) }
}

struct GIFFrameRange: Sendable, Equatable {
  let startIndex: Int
  let endIndexExclusive: Int
}

enum GIFLoopMode: Sendable, Equatable, Hashable {
  case forever
  case once
}

struct GIFEditParameters: Sendable, Equatable {
  var frameRange: GIFFrameRange
  var playbackSpeed: Double
  var loopMode: GIFLoopMode
  var frameRate: GIFCompressionFrameRate = .fps50

  static let speedPresets = (1...12).map { Double($0) / 4 }
}

struct EditedGIFSequence: Sendable, Equatable {
  let sequence: CapturedPNGSequence
  let loopMode: GIFLoopMode
}

enum GIFEditModelError: Error, Sendable, Equatable {
  case emptySequence
  case invalidFrameRange
  case invalidPlaybackSpeed
  case invalidTimestamps
  case unrepresentableTiming
}

enum GIFEditModel {
  static func apply(
    _ parameters: GIFEditParameters,
    to sequence: CapturedPNGSequence
  ) throws -> EditedGIFSequence {
    guard !sequence.frames.isEmpty else { throw GIFEditModelError.emptySequence }

    let range = parameters.frameRange
    guard range.startIndex >= 0,
      range.endIndexExclusive <= sequence.frames.count,
      range.startIndex < range.endIndexExclusive
    else { throw GIFEditModelError.invalidFrameRange }

    guard parameters.playbackSpeed.isFinite, parameters.playbackSpeed > 0 else {
      throw GIFEditModelError.invalidPlaybackSpeed
    }

    let frames = Array(sequence.frames[range.startIndex..<range.endIndexExclusive])
    let timestamps = frames.map(\.timestamp)
    guard timestamps.allSatisfy(\.isFinite) else {
      throw GIFEditModelError.invalidTimestamps
    }
    for index in 1..<timestamps.count where timestamps[index] <= timestamps[index - 1] {
      throw GIFEditModelError.invalidTimestamps
    }

    guard let firstTimestamp = timestamps.first, let lastTimestamp = timestamps.last else {
      throw GIFEditModelError.invalidFrameRange
    }
    var editedFrames: [CapturedPNGFrame] = []
    editedFrames.reserveCapacity(frames.count)
    var previousTimestamp: TimeInterval?

    for frame in frames {
      let editedTimestamp = (frame.timestamp - firstTimestamp) / parameters.playbackSpeed
      guard editedTimestamp.isFinite,
        editedTimestamp >= 0,
        previousTimestamp.map({ editedTimestamp > $0 }) ?? true
      else { throw GIFEditModelError.unrepresentableTiming }
      editedFrames.append(CapturedPNGFrame(url: frame.url, timestamp: editedTimestamp))
      previousTimestamp = editedTimestamp
    }

    let lastSourceIndex = range.endIndexExclusive - 1
    let finalInterval: TimeInterval
    if range.endIndexExclusive < sequence.frames.count {
      finalInterval = sequence.frames[range.endIndexExclusive].timestamp - lastTimestamp
    } else if let duration = sequence.finalFrameDuration {
      finalInterval = duration
    } else if lastSourceIndex > 0 {
      finalInterval = lastTimestamp - sequence.frames[lastSourceIndex - 1].timestamp
    } else {
      finalInterval = 1.0 / 60
    }
    let adjustedFinalInterval = finalInterval / parameters.playbackSpeed
    guard adjustedFinalInterval.isFinite, adjustedFinalInterval > 0 else {
      throw GIFEditModelError.invalidTimestamps
    }

    return EditedGIFSequence(
      sequence: try sample(
        frames: editedFrames, finalFrameDuration: adjustedFinalInterval,
        frameRate: parameters.frameRate),
      loopMode: parameters.loopMode
    )
  }

  /// samples the speed-adjusted timeline, holding sparse frames without adding visual detail.
  /// cumulative centisecond boundaries avoid drift; very short clips retain one 20 ms frame.
  private static func sample(
    frames: [CapturedPNGFrame], finalFrameDuration: TimeInterval,
    frameRate: GIFCompressionFrameRate
  ) throws -> CapturedPNGSequence {
    guard let last = frames.last else { throw GIFEditModelError.emptySequence }
    let duration = last.timestamp + finalFrameDuration
    let slots = ceil(duration * frameRate.framesPerSecond)
    guard duration.isFinite, duration > 0, slots.isFinite, slots < 1_000_000 else {
      throw GIFEditModelError.unrepresentableTiming
    }
    let totalCentiseconds = max(2, (duration * 100).rounded())
    var sampled: [CapturedPNGFrame] = []
    var sourceIndex = 0
    var previousSourceIndex: Int?
    for slot in 0..<max(1, Int(slots)) {
      let time = Double(slot) / frameRate.framesPerSecond
      while sourceIndex + 1 < frames.count,
        frames[sourceIndex + 1].timestamp <= time + 1e-9
      {
        sourceIndex += 1
      }
      let boundary = (time * 100).rounded()
      guard boundary <= totalCentiseconds - 2 else { break }
      if sourceIndex != previousSourceIndex {
        sampled.append(
          CapturedPNGFrame(
            url: frames[sourceIndex].url, timestamp: boundary / 100))
        previousSourceIndex = sourceIndex
      }
    }
    guard let finalFrame = sampled.last else { throw GIFEditModelError.emptySequence }
    return CapturedPNGSequence(
      frames: sampled, finalFrameDuration: totalCentiseconds / 100 - finalFrame.timestamp)
  }

}
