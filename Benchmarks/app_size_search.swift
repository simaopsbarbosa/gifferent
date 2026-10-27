import Foundation

/// runs the production encoder and search adapters on synthetic files without starting capture.
@main
struct AppSizeSearchBenchmark {
  @MainActor
  static func main() async throws {
    let arguments = CommandLine.arguments
    guard arguments.count == 5 else {
      throw NSError(domain: "usage: app_size_search gifski fixture output mode", code: 2)
    }
    let executable = URL(fileURLWithPath: arguments[1])
    let fixture = URL(fileURLWithPath: arguments[2])
    let directory = URL(fileURLWithPath: arguments[3])
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    if arguments[4].hasPrefix("prepare") {
      let frames = try FileManager.default.contentsOfDirectory(
        at: fixture, includingPropertiesForKeys: nil
      )
      .filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
      let sequence = CapturedPNGSequence(
        frames: frames.enumerated().map {
          CapturedPNGFrame(url: $0.element, timestamp: Double($0.offset) / 24)
        })
      let edited: EditedGIFSequence
      if arguments[4] == "prepare-edit" {
        edited = try GIFEditModel.apply(
          GIFEditParameters(
            frameRange: GIFFrameRange(startIndex: 1, endIndexExclusive: frames.count - 1),
            playbackSpeed: 1.7, loopMode: .once), to: sequence)
      } else if arguments[4] == "prepare-single" {
        edited = try GIFEditModel.apply(
          GIFEditParameters(
            frameRange: GIFFrameRange(startIndex: 0, endIndexExclusive: 1),
            playbackSpeed: 2, loopMode: .once), to: sequence)
      } else {
        edited = EditedGIFSequence(sequence: sequence, loopMode: .forever)
      }
      _ = try await ImageIOOriginalGIFEncoder().encode(
        edited.sequence, loopMode: edited.loopMode,
        to: PreviewOutputReservation(
          url: directory.appendingPathComponent("source.gif"), maximumBytes: 512 * 1_024 * 1_024))
      return
    }
    let source = try GIFMetadataInspector().inspect(fixture)
    let quality = arguments[4] == "search100" ? 100 : 90
    let settings = GIFCompressionSettings(scale: .original, qualityPercent: quality)
    let compressor = GifskiCLICompressor(executableURL: executable)
    let clock = ContinuousClock()
    let start = clock.now
    var attempts: [[String: Any]] = []
    let result = try await GIFSizeSearchEngine.search(
      source: source, settings: settings, plan: GIFSizeSearchPlan(settings: settings),
      compress: { candidate in
        let output = directory.appendingPathComponent("attempt-\(attempts.count).gif")
        let attemptStart = clock.now
        let gif = try await compressor.compress(
          source: source, settings: candidate,
          to: CompressedPreviewOutputReservation(
            url: output, maximumBytes: 128 * 1_024 * 1_024, sourceURL: source.url))
        let elapsed = attemptStart.duration(to: clock.now).components
        attempts.append([
          "scale": candidate.scale.rawValue, "fps": candidate.frameRate.rawValue,
          "quality": candidate.qualityPercent, "bytes": gif.fileBytes,
          "seconds": Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
          "width": gif.width, "height": gif.height, "frames": gif.frameCount,
          "duration_cs": gif.durationCentiseconds, "forever": gif.loopsForever,
        ])
        return gif
      },
      discard: {
        if arguments[4] != "review" { try? FileManager.default.removeItem(at: $0.url) }
      })
    let elapsed = start.duration(to: clock.now).components
    let report: [String: Any] = [
      "attempts": attempts, "selected_scale": result.settings.scale.rawValue,
      "selected_fps": result.settings.frameRate.rawValue, "selected_bytes": result.gif.fileBytes,
      "reached_target": result.reachedTarget, "target_bytes": settings.destination.targetBytes,
      "seconds": Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
      "retained_files": try FileManager.default.contentsOfDirectory(atPath: directory.path),
    ]
    let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
  }
}
