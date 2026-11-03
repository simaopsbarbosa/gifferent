import Foundation

@main
struct FrameRateBenchmark {
  static func main() async throws {
    let args = CommandLine.arguments
    guard args.count == 8, let captureRate = Int(args[2]), let count = Int(args[3]),
      let outputRate = Int(args[4]), let rate = GIFCompressionFrameRate(rawValue: outputRate),
      let speed = Double(args[5]), captureRate > 0, count > 0
    else {
      fatalError(
        "usage: helper fixture-directory capture-fps count output-fps speed legacy|edit output.gif")
    }
    let directory = URL(fileURLWithPath: args[1])
    let frames = (0..<count).map { index in
      CapturedPNGFrame(
        url: directory.appendingPathComponent(
          String(format: "frame_%04d.png", index * 60 / captureRate)),
        timestamp: Double(index) / Double(captureRate))
    }
    let captured = CapturedPNGSequence(frames: frames, finalFrameDuration: 1 / Double(captureRate))
    let sequence: CapturedPNGSequence
    if args[6] == "legacy" {
      sequence = captured
    } else {
      sequence = try GIFEditModel.apply(
        GIFEditParameters(
          frameRange: GIFFrameRange(startIndex: 0, endIndexExclusive: count),
          playbackSpeed: speed, loopMode: .forever, frameRate: rate), to: captured
      ).sequence
    }
    let gif = try await ImageIOOriginalGIFEncoder().encode(
      sequence,
      to: PreviewOutputReservation(
        url: URL(fileURLWithPath: args[7]), maximumBytes: 512 * 1_024 * 1_024))
    guard
      gif.durationCentiseconds
        == Int((Double(count) / Double(captureRate) / speed * 100).rounded()),
      gif.loopsForever, gif.width == 640, gif.height == 360,
      args[6] == "legacy" || gif.delaysCentiseconds.allSatisfy({ $0 >= 2 })
    else { fatalError("invalid benchmark GIF") }
    let capturedBytes = try frames.reduce(Int64(0)) { sum, frame in
      sum
        + Int64(
          try FileManager.default.attributesOfItem(atPath: frame.url.path)[.size] as? Int ?? 0)
    }
    let result: [String: Any] = [
      "frames": gif.frameCount, "duration_cs": gif.durationCentiseconds, "bytes": gif.fileBytes,
      "captured_png_bytes": capturedBytes, "width": gif.width, "height": gif.height,
    ]
    print(
      String(
        decoding: try JSONSerialization.data(withJSONObject: result, options: .sortedKeys),
        as: UTF8.self))
  }
}
