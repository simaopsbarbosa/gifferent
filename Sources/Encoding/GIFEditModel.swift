import Foundation

struct GIFFrameRange: Sendable, Equatable {
  let startIndex: Int
  let endIndexExclusive: Int
}

enum GIFLoopMode: Sendable, Equatable {
  case forever
  case once
}

struct GIFEditParameters: Sendable, Equatable {
  var frameRange: GIFFrameRange
  var playbackSpeed: Double
  var loopMode: GIFLoopMode
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
      finalInterval = 1.0 / 24
    }
    let adjustedFinalInterval = finalInterval / parameters.playbackSpeed
    guard adjustedFinalInterval.isFinite, adjustedFinalInterval > 0 else {
      throw GIFEditModelError.invalidTimestamps
    }

    return EditedGIFSequence(
      sequence: CapturedPNGSequence(
        frames: editedFrames, finalFrameDuration: adjustedFinalInterval),
      loopMode: parameters.loopMode
    )
  }
}
