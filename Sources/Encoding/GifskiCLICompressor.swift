import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum GifskiCompressionError: Error, Equatable {
  case invalidExecutable
  case invalidSource
  case invalidQuality
  case unrepresentableTiming
  case invalidFrame
  case frameWorkspaceLimitExceeded
  case outputSizeExceeded
  case processFailed(Int32, String)
  case cancelled
  case invalidOutput
}

/// Local Gifski adapter. The caller supplies the executable so development and release
/// provenance remain explicit; this type never searches PATH or invokes a shell.
struct GifskiCLICompressor: GIFCompressing, Sendable {
  static let maximumFrameWorkspaceBytes: Int64 = 128 * 1_024 * 1_024
  static let maximumFramePixels: Int64 = 32_000_000
  private static let maximumStandardErrorBytes = 64 * 1_024

  let executableURL: URL

  static func availableInMainBundle() -> GifskiCLICompressor? {
    guard let url = Bundle.main.url(forResource: "gifski", withExtension: nil),
      FileManager.default.isExecutableFile(atPath: url.path)
    else { return nil }
    return GifskiCLICompressor(executableURL: url)
  }

  func compress(
    source: EncodedGIF,
    settings: GIFCompressionSettings,
    to reservation: CompressedPreviewOutputReservation
  ) async throws -> EncodedGIF {
    guard executableURL.isFileURL, executableURL.path.hasPrefix("/"),
      FileManager.default.isExecutableFile(atPath: executableURL.path)
    else { throw GifskiCompressionError.invalidExecutable }
    guard settings.isValid else { throw GifskiCompressionError.invalidQuality }
    guard source.url.isFileURL, source.url.path.hasPrefix("/"),
      source.url.standardizedFileURL != reservation.url.standardizedFileURL,
      reservation.sourceURL == source.url.standardizedFileURL,
      reservation.maximumBytes > 0,
      reservation.url.isFileURL, reservation.url.path.hasPrefix("/")
    else { throw GifskiCompressionError.invalidSource }

    let inspectedSource: EncodedGIF
    do {
      inspectedSource = try GIFMetadataInspector().inspect(source.url)
    } catch {
      throw GifskiCompressionError.invalidSource
    }
    guard inspectedSource == source,
      let sample = try? GIFFrameSampler.sample(
        delaysCentiseconds: source.delaysCentiseconds, frameRate: settings.frameRate)
    else { throw GifskiCompressionError.unrepresentableTiming }

    let expectedWidth = settings.scale.expectedDimension(source.width)
    let expectedHeight = settings.scale.expectedDimension(source.height)
    guard expectedWidth > 0, expectedHeight > 0 else {
      throw GifskiCompressionError.invalidSource
    }
    let (sourcePixels, pixelOverflow) =
      Int64(source.width).multipliedReportingOverflow(by: Int64(source.height))
    guard !pixelOverflow, sourcePixels <= Self.maximumFramePixels else {
      throw GifskiCompressionError.invalidSource
    }

    let outputDirectory = reservation.url.deletingLastPathComponent()
    guard Self.isPrivateDirectory(outputDirectory) else {
      throw GifskiCompressionError.invalidOutput
    }
    var destinationInfo = stat()
    guard lstat(reservation.url.path, &destinationInfo) != 0, errno == ENOENT else {
      throw GifskiCompressionError.invalidOutput
    }
    let workingDirectory =
      outputDirectory
      .appendingPathComponent(".gifferent-gifski-\(UUID().uuidString)", isDirectory: true)
    do {
      try FileManager.default.createDirectory(
        at: workingDirectory,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
    } catch {
      throw GifskiCompressionError.invalidOutput
    }
    defer { try? FileManager.default.removeItem(at: workingDirectory) }
    guard Self.isPrivateDirectory(workingDirectory) else {
      throw GifskiCompressionError.invalidOutput
    }

    let frames: [URL]
    let frameTask = Task.detached(priority: .utility) {
      try Self.decodePNGFrames(
        source: source,
        scale: settings.scale,
        sourceIndices: sample.sourceIndices,
        in: workingDirectory,
        maximumBytes: Self.maximumFrameWorkspaceBytes
      )
    }
    do {
      frames = try await withTaskCancellationHandler {
        try await frameTask.value
      } onCancel: {
        frameTask.cancel()
      }
    } catch let error as GifskiCompressionError {
      throw error
    } catch is CancellationError {
      throw GifskiCompressionError.cancelled
    } catch {
      throw GifskiCompressionError.invalidFrame
    }

    let temporaryURL = workingDirectory.appendingPathComponent("output.gif")
    let arguments = Self.arguments(
      frameURLs: frames,
      outputToStandardOutput: true,
      fps: settings.frameRate.label,
      qualityPercent: settings.qualityPercent,
      width: expectedWidth,
      height: expectedHeight,
      loopsForever: source.loopsForever
    )
    let controller = GifskiProcessController()
    var movedOutput = false
    do {
      try await withTaskCancellationHandler {
        try await Task.detached(priority: .utility) {
          try Self.runProcess(
            executableURL: executableURL,
            arguments: arguments,
            temporaryURL: temporaryURL,
            maximumBytes: reservation.maximumBytes,
            controller: controller
          )
        }.value
      } onCancel: {
        controller.cancel()
      }
      try Task.checkCancellation()
      try Self.setFinalFrameDelay(
        in: temporaryURL, centiseconds: sample.expectedDelaysCentiseconds.last ?? 0)
      try FileManager.default.moveItem(at: temporaryURL, to: reservation.url)
      movedOutput = true
      let output = try GIFMetadataInspector().inspect(reservation.url)
      try validateCompressedGIFOutput(
        output, source: source, settings: settings, reservation: reservation)
      return output
    } catch {
      if movedOutput { try? FileManager.default.removeItem(at: reservation.url) }
      if Task.isCancelled || (error as? GifskiCompressionError) == .cancelled {
        throw GifskiCompressionError.cancelled
      }
      throw error
    }
  }

  static func arguments(
    frameURLs: [URL],
    outputToStandardOutput: Bool,
    fps: String,
    qualityPercent: Int,
    width: Int,
    height: Int,
    loopsForever: Bool
  ) -> [String] {
    var arguments = [
      "--fps", fps,
      "--quality", String(qualityPercent),
      "--width", String(width),
      "--height", String(height),
      "--repeat", loopsForever ? "0" : "-1",
      "--no-sort",
      "--quiet",
      "--output", outputToStandardOutput ? "-" : "output.gif",
    ]
    arguments.append(contentsOf: frameURLs.map(\.path))
    return arguments
  }

  static func constantFrameRate(for delaysCentiseconds: [Int]) -> String? {
    guard !delaysCentiseconds.isEmpty, delaysCentiseconds.allSatisfy({ $0 > 0 }) else {
      return nil
    }
    var totalCentiseconds = 0
    for delay in delaysCentiseconds {
      let (nextTotal, overflow) = totalCentiseconds.addingReportingOverflow(delay)
      guard !overflow else { return nil }
      totalCentiseconds = nextTotal
    }
    let rate = Double(delaysCentiseconds.count) * 100 / Double(totalCentiseconds)
    guard rate.isFinite, rate > 0 else { return nil }
    let formattedRate = String(format: "%.12g", locale: Locale(identifier: "en_US_POSIX"), rate)
    guard let exactRate = Double(formattedRate), exactRate.isFinite, exactRate > 0 else {
      return nil
    }
    let timestamps = delaysCentiseconds.indices.map { Double($0) / exactRate }
    guard
      let expected = try? ImageIOOriginalGIFEncoder.frameDelaysCentiseconds(for: timestamps),
      expected == delaysCentiseconds
    else { return nil }
    return formattedRate
  }

  /// corrects Gifski's rounded final frame duration so the total remains exact to the source GIF.
  static func setFinalFrameDelay(in url: URL, centiseconds: Int) throws {
    guard (1...65_535).contains(centiseconds) else {
      throw GifskiCompressionError.unrepresentableTiming
    }
    guard let handle = FileHandle(forUpdatingAtPath: url.path),
      let fileSize = try? handle.seekToEnd(), fileSize >= 14
    else { throw GifskiCompressionError.invalidOutput }
    defer { try? handle.close() }
    try handle.seek(toOffset: 0)

    var offset: UInt64 = 0
    func readByte() throws -> UInt8 {
      guard offset < fileSize,
        let byte = try handle.read(upToCount: 1)?.first
      else { throw GifskiCompressionError.invalidOutput }
      offset += 1
      return byte
    }
    func readBytes(_ count: Int) throws -> Data {
      guard count >= 0, UInt64(count) <= fileSize - offset,
        let bytes = try handle.read(upToCount: count), bytes.count == count
      else { throw GifskiCompressionError.invalidOutput }
      offset += UInt64(count)
      return bytes
    }
    func skip(_ count: UInt64) throws {
      guard count <= fileSize - offset else { throw GifskiCompressionError.invalidOutput }
      offset += count
      try handle.seek(toOffset: offset)
    }
    func skipSubBlocks(initialBlockSize: Bool) throws {
      if initialBlockSize {
        let count = UInt64(try readByte())
        try skip(count)
      }
      while true {
        let count = UInt64(try readByte())
        if count == 0 { return }
        try skip(count)
      }
    }

    let header = try readBytes(6)
    guard header.elementsEqual("GIF87a".utf8) || header.elementsEqual("GIF89a".utf8) else {
      throw GifskiCompressionError.invalidOutput
    }
    let screen = try readBytes(7)
    let packed = screen[4]
    if packed & 0x80 != 0 { try skip(UInt64(3 * (1 << (Int(packed & 0x07) + 1)))) }
    var delayOffsets: [UInt64] = []
    var pendingDelayOffset: UInt64?
    while offset < fileSize {
      let introducer = try readByte()
      switch introducer {
      case 0x3B:
        guard offset == fileSize, let delayOffset = delayOffsets.last else {
          throw GifskiCompressionError.invalidOutput
        }
        try handle.seek(toOffset: delayOffset)
        try handle.write(
          contentsOf: Data([
            UInt8(centiseconds & 0xff), UInt8((centiseconds >> 8) & 0xff),
          ]))
        try handle.synchronize()
        return
      case 0x21:
        let label = try readByte()
        if label == 0xF9 {
          guard try readByte() == 4 else { throw GifskiCompressionError.invalidOutput }
          try skip(1)
          pendingDelayOffset = offset
          try skip(2)
          try skip(2)
        } else {
          try skipSubBlocks(initialBlockSize: label == 0xFF)
        }
      case 0x2C:
        let descriptor = try readBytes(9)
        let imagePacked = descriptor[8]
        if imagePacked & 0x80 != 0 { try skip(UInt64(3 * (1 << (Int(imagePacked & 0x07) + 1)))) }
        try skip(1)
        try skipSubBlocks(initialBlockSize: false)
        if let pendingDelayOffset { delayOffsets.append(UInt64(pendingDelayOffset)) }
        pendingDelayOffset = nil
      default:
        throw GifskiCompressionError.invalidOutput
      }
    }
    throw GifskiCompressionError.invalidOutput
  }

  static func decodePNGFrames(
    source: EncodedGIF,
    scale: GIFCompressionScale,
    sourceIndices: [Int]? = nil,
    in directory: URL,
    maximumBytes: Int64
  ) throws -> [URL] {
    guard maximumBytes > 0,
      let imageSource = CGImageSourceCreateWithURL(source.url as CFURL, nil),
      CGImageSourceGetCount(imageSource) == source.frameCount
    else { throw GifskiCompressionError.invalidSource }
    let indices = sourceIndices ?? Array(0..<source.frameCount)
    guard !indices.isEmpty, indices.allSatisfy({ $0 >= 0 && $0 < source.frameCount }) else {
      throw GifskiCompressionError.invalidSource
    }
    var frames: [URL] = []
    var totalBytes: Int64 = 0
    for (outputIndex, index) in indices.enumerated() {
      try Task.checkCancellation()
      guard
        let decoded = CGImageSourceCreateImageAtIndex(
          imageSource, index,
          [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true,
          ] as CFDictionary),
        decoded.width == source.width, decoded.height == source.height,
        let scaled = makeScaledImage(decoded, scale: scale)
      else { throw GifskiCompressionError.invalidFrame }
      let url = directory.appendingPathComponent(String(format: "frame-%08d.png", outputIndex))
      let remainingBytes = maximumBytes - totalBytes
      guard remainingBytes > 0 else {
        throw GifskiCompressionError.frameWorkspaceLimitExceeded
      }
      let writer = try BoundedPNGWriter(url: url, maximumBytes: remainingBytes)
      let callbacks = CGDataConsumerCallbacks(
        putBytes: { info, buffer, count in
          guard let info else { return 0 }
          return Unmanaged<BoundedPNGWriter>.fromOpaque(info)
            .takeUnretainedValue().write(buffer, count: count)
        },
        releaseConsumer: nil
      )
      let consumer = withUnsafePointer(to: callbacks) {
        CGDataConsumer(info: Unmanaged.passUnretained(writer).toOpaque(), cbks: $0)
      }
      guard let consumer,
        let destination = CGImageDestinationCreateWithDataConsumer(
          consumer, UTType.png.identifier as CFString, 1, nil)
      else { throw GifskiCompressionError.invalidFrame }
      CGImageDestinationAddImage(destination, scaled, nil)
      guard CGImageDestinationFinalize(destination) else {
        if writer.exceededLimit { throw GifskiCompressionError.frameWorkspaceLimitExceeded }
        throw GifskiCompressionError.invalidFrame
      }
      guard !writer.exceededLimit, !writer.writeFailed else {
        throw writer.exceededLimit
          ? GifskiCompressionError.frameWorkspaceLimitExceeded
          : GifskiCompressionError.invalidFrame
      }
      var fileInfo = stat()
      guard lstat(url.path, &fileInfo) == 0, fileInfo.st_mode & S_IFMT == S_IFREG,
        fileInfo.st_size > 0
      else { throw GifskiCompressionError.invalidFrame }
      let (nextBytes, overflow) = totalBytes.addingReportingOverflow(Int64(fileInfo.st_size))
      guard !overflow, nextBytes <= maximumBytes else {
        throw GifskiCompressionError.frameWorkspaceLimitExceeded
      }
      totalBytes = nextBytes
      frames.append(url)
    }
    guard frames.count == indices.count else { throw GifskiCompressionError.invalidFrame }
    return frames
  }

  private final class BoundedPNGWriter {
    private let descriptor: Int32
    private let maximumBytes: Int64
    private(set) var bytesWritten: Int64 = 0
    private(set) var exceededLimit = false
    private(set) var writeFailed = false

    init(url: URL, maximumBytes: Int64) throws {
      self.maximumBytes = maximumBytes
      descriptor = open(
        url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, S_IRUSR | S_IWUSR)
      guard descriptor >= 0 else { throw GifskiCompressionError.invalidFrame }
    }

    deinit { close(descriptor) }

    func write(_ buffer: UnsafeRawPointer, count: Int) -> Int {
      guard count > 0 else { return 0 }
      let (nextBytes, overflow) = bytesWritten.addingReportingOverflow(Int64(count))
      guard !overflow, nextBytes <= maximumBytes else {
        exceededLimit = true
        return 0
      }
      var offset = 0
      while offset < count {
        let written = Darwin.write(
          descriptor, buffer.advanced(by: offset), count - offset)
        if written < 0, errno == EINTR { continue }
        guard written > 0 else {
          writeFailed = true
          return 0
        }
        offset += written
      }
      bytesWritten = nextBytes
      return count
    }
  }

  private static func makeScaledImage(_ image: CGImage, scale: GIFCompressionScale) -> CGImage? {
    let width = scale.expectedDimension(image.width)
    let height = scale.expectedDimension(image.height)
    guard width > 0, height > 0,
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }

  private static func runProcess(
    executableURL: URL,
    arguments: [String],
    temporaryURL: URL,
    maximumBytes: Int64,
    controller: GifskiProcessController
  ) throws {
    let outputDescriptor = open(
      temporaryURL.path,
      O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
      S_IRUSR | S_IWUSR
    )
    guard outputDescriptor >= 0 else { throw GifskiCompressionError.invalidOutput }
    defer { close(outputDescriptor) }

    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.executableURL = executableURL
    process.arguments = arguments
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    controller.install(process)
    do {
      try process.run()
    } catch {
      controller.finish()
      throw GifskiCompressionError.processFailed(-1, "could not launch")
    }
    controller.didLaunch()

    let outputQueue = DispatchQueue(label: "gifferent.gifski.stdout")
    let errorQueue = DispatchQueue(label: "gifferent.gifski.stderr")
    let group = DispatchGroup()
    let result = GifskiProcessResult()
    group.enter()
    outputQueue.async {
      defer {
        outputPipe.fileHandleForReading.closeFile()
        group.leave()
      }
      do {
        while true {
          let chunk = try outputPipe.fileHandleForReading.read(upToCount: 64 * 1_024) ?? Data()
          if chunk.isEmpty { break }
          let remaining = maximumBytes - result.bytesWritten
          if Int64(chunk.count) > remaining {
            if remaining > 0 {
              try writeAll(Data(chunk.prefix(Int(remaining))), to: outputDescriptor)
              result.addBytes(remaining)
            }
            result.setOutputLimitExceeded()
            controller.terminate()
            continue
          }
          try writeAll(chunk, to: outputDescriptor)
          result.addBytes(Int64(chunk.count))
        }
      } catch {
        result.setWriteFailure()
        controller.terminate()
      }
    }
    group.enter()
    errorQueue.async {
      defer {
        errorPipe.fileHandleForReading.closeFile()
        group.leave()
      }
      while true {
        do {
          guard let chunk = try errorPipe.fileHandleForReading.read(upToCount: 8 * 1_024),
            !chunk.isEmpty
          else { break }
          result.appendStandardError(chunk, maximumBytes: Self.maximumStandardErrorBytes)
        } catch { break }
      }
    }
    process.waitUntilExit()
    group.wait()
    controller.finish()
    if controller.wasCancelled { throw GifskiCompressionError.cancelled }
    switch result.failure {
    case .outputSizeExceeded: throw GifskiCompressionError.outputSizeExceeded
    case .writeFailure: throw GifskiCompressionError.invalidOutput
    case nil: break
    }
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
      throw GifskiCompressionError.processFailed(
        process.terminationStatus, result.standardError)
    }
    guard result.bytesWritten > 0 else { throw GifskiCompressionError.invalidOutput }
  }

  private static func writeAll(_ data: Data, to descriptor: Int32) throws {
    try data.withUnsafeBytes { buffer in
      guard let baseAddress = buffer.baseAddress else { return }
      var offset = 0
      while offset < buffer.count {
        let written = write(descriptor, baseAddress.advanced(by: offset), buffer.count - offset)
        if written < 0, errno == EINTR { continue }
        guard written > 0 else { throw GifskiCompressionError.invalidOutput }
        offset += written
      }
    }
  }

  private static func isPrivateDirectory(_ url: URL) -> Bool {
    var info = stat()
    return lstat(url.path, &info) == 0
      && info.st_mode & S_IFMT == S_IFDIR
      && info.st_uid == geteuid()
      && info.st_mode & 0o077 == 0
  }
}

private final class GifskiProcessController: @unchecked Sendable {
  private let lock = NSLock()
  private var process: Process?
  private var cancelled = false

  var wasCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }

  func install(_ process: Process) {
    lock.lock()
    self.process = process
    let cancelNow = cancelled
    lock.unlock()
    if cancelNow { terminate(process) }
  }

  func cancel() {
    lock.lock()
    cancelled = true
    let current = process
    lock.unlock()
    if let current { terminate(current) }
  }

  func didLaunch() {
    lock.lock()
    let cancelNow = cancelled
    let current = process
    lock.unlock()
    if cancelNow, let current { terminate(current) }
  }

  func terminate() {
    lock.lock()
    let current = process
    lock.unlock()
    if let current { terminate(current) }
  }

  func finish() {
    lock.lock()
    process = nil
    lock.unlock()
  }

  private func terminate(_ process: Process) {
    if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
  }
}

private final class GifskiProcessResult: @unchecked Sendable {
  enum Failure { case outputSizeExceeded, writeFailure }
  private let lock = NSLock()
  private var bytes = Int64(0)
  private var storedFailure: Failure?
  private var stderr = Data()

  var bytesWritten: Int64 {
    lock.lock()
    defer { lock.unlock() }
    return bytes
  }

  var failure: Failure? {
    lock.lock()
    defer { lock.unlock() }
    return storedFailure
  }

  var standardError: String {
    lock.lock()
    defer { lock.unlock() }
    return String(decoding: stderr, as: UTF8.self)
  }

  func addBytes(_ count: Int64) {
    lock.lock()
    bytes += count
    lock.unlock()
  }

  func setOutputLimitExceeded() { set(.outputSizeExceeded) }
  func setWriteFailure() { set(.writeFailure) }

  func appendStandardError(_ data: Data, maximumBytes: Int) {
    lock.lock()
    defer { lock.unlock() }
    let remaining = maximumBytes - stderr.count
    if remaining > 0 { stderr.append(contentsOf: data.prefix(remaining)) }
  }

  private func set(_ failure: Failure) {
    lock.lock()
    if storedFailure == nil { storedFailure = failure }
    lock.unlock()
  }
}
