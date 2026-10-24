import CoreGraphics
import Darwin
import Foundation
import ImageIO

enum ExperimentalGIFScale: Sendable, CaseIterable {
  case original
  case seventyFivePercent
  case fiftyPercent
  case twentyFivePercent

  fileprivate var resizeArgument: String? {
    switch self {
    case .original: nil
    case .seventyFivePercent: "75%"
    case .fiftyPercent: "50%"
    case .twentyFivePercent: "25%"
    }
  }

  fileprivate var scaleFactor: Double? {
    switch self {
    case .original: nil
    case .seventyFivePercent: 0.75
    case .fiftyPercent: 0.5
    case .twentyFivePercent: 0.25
    }
  }
}

enum ExperimentalImageMagickCompressionError: Error, Equatable {
  case invalidExecutable
  case invalidSource
  case invalidDiffusionAmount
  case outputSizeExceeded
  case processFailed(Int32, String)
  case cancelled
  case invalidOutput
}

struct ExperimentalCompressedGIF: Sendable, Equatable {
  let url: URL
  let width: Int
  let height: Int
  let frameCount: Int
  let delaysCentiseconds: [Int]
  let loopCount: Int?
  let fileBytes: Int64
}

/// an isolated prototype. it is not wired into the app or selected for release.
struct ExperimentalImageMagickCompressor: Sendable {
  static let defaultDiffusionAmount = 35
  private static let maximumStandardErrorBytes = 64 * 1_024

  func compress(
    _ sourceURL: URL,
    executableURL: URL,
    scale: ExperimentalGIFScale,
    diffusionAmount: Int = Self.defaultDiffusionAmount,
    to reservation: CompressedPreviewOutputReservation
  ) async throws -> ExperimentalCompressedGIF {
    guard executableURL.isFileURL, executableURL.path.hasPrefix("/"),
      FileManager.default.isExecutableFile(atPath: executableURL.path)
    else { throw ExperimentalImageMagickCompressionError.invalidExecutable }
    guard (0...100).contains(diffusionAmount), diffusionAmount.isMultiple(of: 5) else {
      throw ExperimentalImageMagickCompressionError.invalidDiffusionAmount
    }
    guard sourceURL.isFileURL, sourceURL.path.hasPrefix("/"),
      sourceURL.standardizedFileURL != reservation.url.standardizedFileURL,
      reservation.sourceURL == sourceURL.standardizedFileURL
    else { throw ExperimentalImageMagickCompressionError.invalidSource }

    let sourceMetadata: GIFAnimationMetadata
    do {
      sourceMetadata = try GIFAnimationMetadata.read(from: sourceURL)
    } catch {
      throw ExperimentalImageMagickCompressionError.invalidSource
    }

    let destination = reservation.url
    guard destination.isFileURL, destination.path.hasPrefix("/"),
      let cacheDirectory = reservation.cacheDirectory,
      cacheDirectory.deletingLastPathComponent().standardizedFileURL
        == destination.deletingLastPathComponent().standardizedFileURL,
      reservation.maximumCacheBytes > 0,
      Self.isPrivateDirectory(cacheDirectory)
    else {
      throw ExperimentalImageMagickCompressionError.invalidOutput
    }
    let temporaryURL = destination.deletingLastPathComponent()
      .appendingPathComponent(".gifferent-compress-\(UUID().uuidString).gif")
    var destinationInfo = stat()
    guard lstat(destination.path, &destinationInfo) != 0, errno == ENOENT else {
      throw ExperimentalImageMagickCompressionError.invalidOutput
    }

    let arguments = Self.arguments(
      sourceURL: sourceURL,
      scale: scale,
      diffusionAmount: diffusionAmount,
      cacheDirectory: cacheDirectory,
      maximumCacheBytes: reservation.maximumCacheBytes
    )
    let controller = ImageMagickProcessController()
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

      let resultMetadata = try GIFAnimationMetadata.read(from: temporaryURL)
      guard resultMetadata.frameCount == sourceMetadata.frameCount,
        resultMetadata.delaysCentiseconds == sourceMetadata.delaysCentiseconds,
        resultMetadata.loopCount == sourceMetadata.loopCount,
        scale.matches(
          width: resultMetadata.width,
          height: resultMetadata.height,
          sourceWidth: sourceMetadata.width,
          sourceHeight: sourceMetadata.height
        )
      else { throw ExperimentalImageMagickCompressionError.invalidOutput }

      let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
      guard let number = attributes[.size] as? NSNumber,
        number.int64Value > 0, number.int64Value <= reservation.maximumBytes
      else { throw ExperimentalImageMagickCompressionError.outputSizeExceeded }

      try Task.checkCancellation()
      try FileManager.default.moveItem(at: temporaryURL, to: destination)
      return ExperimentalCompressedGIF(
        url: destination,
        width: resultMetadata.width,
        height: resultMetadata.height,
        frameCount: resultMetadata.frameCount,
        delaysCentiseconds: resultMetadata.delaysCentiseconds,
        loopCount: resultMetadata.loopCount,
        fileBytes: number.int64Value
      )
    } catch {
      try? FileManager.default.removeItem(at: temporaryURL)
      if Task.isCancelled || (error as? ExperimentalImageMagickCompressionError) == .cancelled {
        throw ExperimentalImageMagickCompressionError.cancelled
      }
      throw error
    }
  }

  static func arguments(
    sourceURL: URL,
    scale: ExperimentalGIFScale,
    diffusionAmount: Int,
    cacheDirectory: URL,
    maximumCacheBytes: Int64
  ) -> [String] {
    // these pixel-cache limits still need full-image resource benchmarks before UI use.
    var arguments = [
      "-limit", "memory", "256MiB",
      "-limit", "map", "512MiB",
      "-limit", "disk", String(maximumCacheBytes),
      "-limit", "thread", "2",
      "-define", "registry:temporary-path=\(cacheDirectory.path)",
      sourceURL.path,
      "-coalesce",
    ]
    if let resize = scale.resizeArgument {
      arguments.append(contentsOf: ["-resize", resize])
    }
    arguments.append(contentsOf: [
      "-dither", "FloydSteinberg",
      "-define", "dither:diffusion-amount=\(diffusionAmount)%",
      "-colors", "256",
      "-layers", "Optimize",
      "gif:-",
    ])
    return arguments
  }

  private static func isPrivateDirectory(_ url: URL) -> Bool {
    var info = stat()
    return lstat(url.path, &info) == 0
      && info.st_mode & S_IFMT == S_IFDIR
      && info.st_uid == geteuid()
      && info.st_mode & 0o077 == 0
  }

  private static func runProcess(
    executableURL: URL,
    arguments: [String],
    temporaryURL: URL,
    maximumBytes: Int64,
    controller: ImageMagickProcessController
  ) throws {
    guard maximumBytes > 0 else {
      throw ExperimentalImageMagickCompressionError.outputSizeExceeded
    }
    let outputDescriptor = open(
      temporaryURL.path,
      O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
      S_IRUSR | S_IWUSR
    )
    guard outputDescriptor >= 0 else {
      throw ExperimentalImageMagickCompressionError.invalidOutput
    }
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
      throw ExperimentalImageMagickCompressionError.processFailed(-1, "could not launch")
    }
    controller.didLaunch()

    let ioQueue = DispatchQueue(label: "gifferent.imagemagick.stdout")
    let errorQueue = DispatchQueue(label: "gifferent.imagemagick.stderr")
    let group = DispatchGroup()
    let failure = ImageMagickProcessFailure()

    group.enter()
    ioQueue.async {
      defer {
        outputPipe.fileHandleForReading.closeFile()
        group.leave()
      }
      do {
        while true {
          let chunk = try outputPipe.fileHandleForReading.read(upToCount: 64 * 1_024) ?? Data()
          if chunk.isEmpty { break }
          let remaining = maximumBytes - failure.bytesWritten
          if Int64(chunk.count) > remaining {
            if remaining > 0 {
              try writeAll(Data(chunk.prefix(Int(remaining))), to: outputDescriptor)
              failure.addBytes(remaining)
            }
            failure.set(.outputSizeExceeded)
            controller.terminate()
            continue
          }
          try writeAll(chunk, to: outputDescriptor)
          failure.addBytes(Int64(chunk.count))
        }
      } catch {
        failure.set(.writeFailure)
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
          failure.appendStandardError(chunk, maximumBytes: maximumStandardErrorBytes)
        } catch {
          break
        }
      }
    }

    process.waitUntilExit()
    group.wait()
    controller.finish()

    if controller.wasCancelled {
      throw ExperimentalImageMagickCompressionError.cancelled
    }
    switch failure.failure {
    case .outputSizeExceeded:
      throw ExperimentalImageMagickCompressionError.outputSizeExceeded
    case .writeFailure:
      throw ExperimentalImageMagickCompressionError.invalidOutput
    case nil:
      break
    }
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
      throw ExperimentalImageMagickCompressionError.processFailed(
        process.terminationStatus,
        failure.standardError
      )
    }
    guard failure.bytesWritten > 0 else {
      throw ExperimentalImageMagickCompressionError.invalidOutput
    }
  }

  private static func writeAll(_ data: Data, to descriptor: Int32) throws {
    try data.withUnsafeBytes { buffer in
      guard let baseAddress = buffer.baseAddress else { return }
      var offset = 0
      while offset < buffer.count {
        let written = write(descriptor, baseAddress.advanced(by: offset), buffer.count - offset)
        if written < 0, errno == EINTR { continue }
        guard written > 0 else { throw ExperimentalImageMagickCompressionError.invalidOutput }
        offset += written
      }
    }
  }
}

private struct GIFAnimationMetadata {
  let width: Int
  let height: Int
  let frameCount: Int
  let delaysCentiseconds: [Int]
  let loopCount: Int?

  static func read(from url: URL) throws -> Self {
    let canvasAndFrames = try GIFFrameDescriptorInspector.inspect(url)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
    else { throw ExperimentalImageMagickCompressionError.invalidOutput }
    let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] ?? [:]
    let frameCount = CGImageSourceGetCount(source)
    guard frameCount > 0, canvasAndFrames.frames.count == frameCount else {
      throw ExperimentalImageMagickCompressionError.invalidOutput
    }
    var delays: [Int] = []
    for index in 0..<frameCount {
      guard
        let frameProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
          as? [CFString: Any],
        let frameGIF = frameProperties[kCGImagePropertyGIFDictionary] as? [CFString: Any],
        let delay = frameGIF[kCGImagePropertyGIFUnclampedDelayTime] as? Double
          ?? frameGIF[kCGImagePropertyGIFDelayTime] as? Double,
        delay.isFinite, delay > 0,
        let image = CGImageSourceCreateImageAtIndex(source, index, nil),
        image.width > 0, image.height > 0,
        image.width <= canvasAndFrames.width,
        image.height <= canvasAndFrames.height
      else { throw ExperimentalImageMagickCompressionError.invalidOutput }
      let delayCentiseconds = Int((delay * 100).rounded(.toNearestOrAwayFromZero))
      guard delayCentiseconds > 0 else {
        throw ExperimentalImageMagickCompressionError.invalidOutput
      }
      delays.append(delayCentiseconds)
    }
    return Self(
      width: canvasAndFrames.width,
      height: canvasAndFrames.height,
      frameCount: frameCount,
      delaysCentiseconds: delays,
      loopCount: gif[kCGImagePropertyGIFLoopCount] as? Int
    )
  }
}

struct GIFFrameDescriptorInspector {
  struct Rectangle: Equatable {
    let left: Int
    let top: Int
    let width: Int
    let height: Int
  }

  struct CanvasAndFrames: Equatable {
    let width: Int
    let height: Int
    let frames: [Rectangle]
  }

  static func inspect(_ url: URL) throws -> CanvasAndFrames {
    var fileInfo = stat()
    guard lstat(url.path, &fileInfo) == 0,
      fileInfo.st_mode & S_IFMT == S_IFREG,
      fileInfo.st_size > 0
    else { throw ExperimentalImageMagickCompressionError.invalidOutput }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let size = try handle.seekToEnd()
    try handle.seek(toOffset: 0)
    let reader = GIFStreamReader(handle: handle, fileSize: size)
    let signature = try reader.readBytes(6)
    guard signature == Array("GIF87a".utf8) || signature == Array("GIF89a".utf8) else {
      throw ExperimentalImageMagickCompressionError.invalidOutput
    }
    let logicalScreen = try reader.readBytes(7)
    let width = littleEndian(logicalScreen[0], logicalScreen[1])
    let height = littleEndian(logicalScreen[2], logicalScreen[3])
    guard width > 0, height > 0 else {
      throw ExperimentalImageMagickCompressionError.invalidOutput
    }
    if logicalScreen[4] & 0x80 != 0 {
      let entries = 1 << (Int(logicalScreen[4] & 0x07) + 1)
      try reader.skip(entries * 3)
    }

    var frames: [Rectangle] = []
    while let introducer = try reader.readByte() {
      switch introducer {
      case 0x3B:
        guard try reader.isAtEnd(), !frames.isEmpty else {
          throw ExperimentalImageMagickCompressionError.invalidOutput
        }
        return CanvasAndFrames(width: width, height: height, frames: frames)
      case 0x21:
        guard try reader.readByte() != nil else {
          throw ExperimentalImageMagickCompressionError.invalidOutput
        }
        try reader.skipSubBlocks()
      case 0x2C:
        let descriptor = try reader.readBytes(9)
        let rectangle = Rectangle(
          left: littleEndian(descriptor[0], descriptor[1]),
          top: littleEndian(descriptor[2], descriptor[3]),
          width: littleEndian(descriptor[4], descriptor[5]),
          height: littleEndian(descriptor[6], descriptor[7])
        )
        guard rectangle.width > 0, rectangle.height > 0,
          rectangle.left + rectangle.width <= width,
          rectangle.top + rectangle.height <= height
        else { throw ExperimentalImageMagickCompressionError.invalidOutput }
        frames.append(rectangle)
        if descriptor[8] & 0x80 != 0 {
          let entries = 1 << (Int(descriptor[8] & 0x07) + 1)
          try reader.skip(entries * 3)
        }
        guard try reader.readByte() != nil else {
          throw ExperimentalImageMagickCompressionError.invalidOutput
        }
        try reader.skipSubBlocks()
      default:
        throw ExperimentalImageMagickCompressionError.invalidOutput
      }
    }
    throw ExperimentalImageMagickCompressionError.invalidOutput
  }

  private static func littleEndian(_ low: UInt8, _ high: UInt8) -> Int {
    Int(low) | (Int(high) << 8)
  }
}

private struct GIFStreamReader {
  let handle: FileHandle
  let fileSize: UInt64

  func isAtEnd() throws -> Bool {
    try handle.offset() == fileSize
  }

  func readByte() throws -> UInt8? {
    guard try handle.offset() < fileSize else { return nil }
    return try readBytes(1).first
  }

  func readBytes(_ count: Int) throws -> [UInt8] {
    guard count >= 0,
      UInt64(count) <= fileSize - (try handle.offset()),
      let data = try handle.read(upToCount: count), data.count == count
    else { throw ExperimentalImageMagickCompressionError.invalidOutput }
    return Array(data)
  }

  func skip(_ count: Int) throws {
    guard count >= 0,
      UInt64(count) <= fileSize - (try handle.offset())
    else { throw ExperimentalImageMagickCompressionError.invalidOutput }
    try handle.seek(toOffset: try handle.offset() + UInt64(count))
  }

  func skipSubBlocks() throws {
    while true {
      guard let length = try readByte() else {
        throw ExperimentalImageMagickCompressionError.invalidOutput
      }
      if length == 0 { return }
      try skip(Int(length))
    }
  }
}

extension ExperimentalGIFScale {
  fileprivate func matches(width: Int, height: Int, sourceWidth: Int, sourceHeight: Int) -> Bool {
    guard width > 0, height > 0 else { return false }
    guard let percentage = scaleFactor else {
      return width == sourceWidth && height == sourceHeight
    }
    let expectedWidth = Int((Double(sourceWidth) * percentage).rounded(.toNearestOrAwayFromZero))
    let expectedHeight = Int((Double(sourceHeight) * percentage).rounded(.toNearestOrAwayFromZero))
    return abs(width - expectedWidth) <= 1 && abs(height - expectedHeight) <= 1
  }
}

private final class ImageMagickProcessController: @unchecked Sendable {
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
    let cancelImmediately = cancelled
    lock.unlock()
    if cancelImmediately { killIfRunning(process) }
  }

  func cancel() {
    lock.lock()
    cancelled = true
    let current = process
    lock.unlock()
    if let current { killIfRunning(current) }
  }

  func didLaunch() {
    lock.lock()
    let cancelImmediately = cancelled
    let current = process
    lock.unlock()
    if cancelImmediately, let current { killIfRunning(current) }
  }

  func terminate() {
    lock.lock()
    let current = process
    lock.unlock()
    if let current { killIfRunning(current) }
  }

  func finish() {
    lock.lock()
    process = nil
    lock.unlock()
  }

  private func killIfRunning(_ process: Process) {
    guard process.isRunning else { return }
    _ = kill(process.processIdentifier, SIGKILL)
  }
}

private final class ImageMagickProcessFailure: @unchecked Sendable {
  enum Kind { case outputSizeExceeded, writeFailure }

  private let lock = NSLock()
  private var bytes = Int64(0)
  private var error: Kind?
  private var stderr = Data()

  var bytesWritten: Int64 {
    lock.lock()
    defer { lock.unlock() }
    return bytes
  }

  var failure: Kind? {
    lock.lock()
    defer { lock.unlock() }
    return error
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

  func set(_ kind: Kind) {
    lock.lock()
    if error == nil { error = kind }
    lock.unlock()
  }

  func appendStandardError(_ data: Data, maximumBytes: Int) {
    lock.lock()
    defer { lock.unlock() }
    let remaining = maximumBytes - stderr.count
    if remaining > 0 { stderr.append(contentsOf: data.prefix(remaining)) }
  }
}
