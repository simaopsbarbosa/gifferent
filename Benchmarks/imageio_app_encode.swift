import Foundation

@main
struct ImageIOAppEncoderBenchmark {
  static func main() async throws {
    if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--validate" {
      let url = URL(fileURLWithPath: CommandLine.arguments[2])
      do {
        let result = try GIFMetadataInspector().inspect(url)
        print(
          "validated width=\(result.width) height=\(result.height) frames=\(result.frameCount) "
            + "duration_cs=\(result.durationCentiseconds) loops_forever=\(result.loopsForever) "
            + "bytes=\(result.fileBytes)"
        )
      } catch {
        fputs("GIF metadata validation failed: \(error)\n", stderr)
        exit(1)
      }
      return
    }

    guard CommandLine.arguments.count >= 4,
      let framesPerSecond = Double(CommandLine.arguments[1]),
      framesPerSecond.isFinite,
      framesPerSecond > 0
    else {
      fputs(
        "usage: imageio_app_encode fps output.gif frame.png... | --validate input.gif\n", stderr)
      exit(2)
    }

    let output = URL(fileURLWithPath: CommandLine.arguments[2])
    let frames = CommandLine.arguments.dropFirst(3).enumerated().map { index, path in
      CapturedPNGFrame(
        url: URL(fileURLWithPath: path),
        timestamp: Double(index) / framesPerSecond
      )
    }
    let result = try await ImageIOOriginalGIFEncoder().encode(
      CapturedPNGSequence(frames: frames),
      to: PreviewOutputReservation(url: output, maximumBytes: 512 * 1_024 * 1_024)
    )
    guard result.loopsForever else {
      fputs("candidate encoder returned a GIF without infinite looping\n", stderr)
      exit(1)
    }
  }
}
