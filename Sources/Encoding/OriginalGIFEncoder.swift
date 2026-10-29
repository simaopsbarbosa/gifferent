import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum OriginalGIFEncodingError: Error, Equatable {
  case invalidSequence
  case invalidTimestamp
  case unrepresentableTiming
  case invalidFrame
  case inconsistentDimensions
  case destinationCreationFailed
  case encodingFailed
  case outputSizeExceeded
  case invalidOutput
  case cancelled
}

struct EncodedGIF: Sendable, Equatable {
  let url: URL
  let width: Int
  let height: Int
  let frameCount: Int
  let delaysCentiseconds: [Int]
  let durationCentiseconds: Int
  let loopsForever: Bool
  let fileBytes: Int64
}

enum GIFLoopExtensionParserError: Error, Equatable {
  case malformedGIF
}

enum GIFLoopExtensionParser {
  private static let netscapeIdentifier = Array("NETSCAPE2.0".utf8)
  private static let animationExtensionsIdentifier = Array("ANIMEXTS1.0".utf8)

  static func containsLoopingApplicationExtension(in data: Data) throws -> Bool {
    try data.withUnsafeBytes { bytes in
      try containsLoopingApplicationExtension(in: bytes)
    }
  }

  static func containsLoopingApplicationExtension(in data: UnsafeRawBufferPointer) throws -> Bool {
    guard data.count >= 13, let baseAddress = data.baseAddress else {
      throw GIFLoopExtensionParserError.malformedGIF
    }
    let bytes = UnsafeBufferPointer(
      start: baseAddress.assumingMemoryBound(to: UInt8.self), count: data.count)
    guard
      bytes[0..<6].elementsEqual("GIF87a".utf8)
        || bytes[0..<6].elementsEqual("GIF89a".utf8)
    else { throw GIFLoopExtensionParserError.malformedGIF }

    var reader = GIFByteReader(bytes: bytes, offset: 13)
    var containsLoopingExtension = false
    let screenPackedFields = bytes[10]
    if screenPackedFields & 0x80 != 0 {
      let colorTableEntries = 1 << (Int(screenPackedFields & 0x07) + 1)
      try reader.skip(colorTableEntries * 3)
    }

    while let introducer = try reader.readByte() {
      switch introducer {
      case 0x3B:
        guard reader.isAtEnd else { throw GIFLoopExtensionParserError.malformedGIF }
        return containsLoopingExtension
      case 0x21:
        guard let label = try reader.readByte() else {
          throw GIFLoopExtensionParserError.malformedGIF
        }
        if label == 0xFF {
          guard let identifierLength = try reader.readByte() else {
            throw GIFLoopExtensionParserError.malformedGIF
          }
          let identifier = try reader.readBytes(Int(identifierLength))
          let isLoopingIdentifier =
            identifier == netscapeIdentifier
            || identifier == animationExtensionsIdentifier
          try reader.skipSubBlocks()
          containsLoopingExtension = containsLoopingExtension || isLoopingIdentifier
        } else {
          try reader.skipSubBlocks()
        }
      case 0x2C:
        let imageDescriptor = try reader.readBytes(9)
        let imagePackedFields = imageDescriptor[8]
        if imagePackedFields & 0x80 != 0 {
          let colorTableEntries = 1 << (Int(imagePackedFields & 0x07) + 1)
          try reader.skip(colorTableEntries * 3)
        }
        guard try reader.readByte() != nil else {
          throw GIFLoopExtensionParserError.malformedGIF
        }
        try reader.skipSubBlocks()
      default:
        throw GIFLoopExtensionParserError.malformedGIF
      }
    }
    throw GIFLoopExtensionParserError.malformedGIF
  }
}

private struct GIFByteReader {
  let bytes: UnsafeBufferPointer<UInt8>
  private(set) var offset: Int

  var isAtEnd: Bool { offset == bytes.count }

  mutating func readByte() throws -> UInt8? {
    guard offset < bytes.count else { return nil }
    defer { offset += 1 }
    return bytes[offset]
  }

  mutating func readBytes(_ count: Int) throws -> [UInt8] {
    guard count >= 0, count <= bytes.count - offset else {
      throw GIFLoopExtensionParserError.malformedGIF
    }
    defer { offset += count }
    return Array(bytes[offset..<(offset + count)])
  }

  mutating func skip(_ count: Int) throws {
    guard count >= 0, count <= bytes.count - offset else {
      throw GIFLoopExtensionParserError.malformedGIF
    }
    offset += count
  }

  mutating func skipSubBlocks() throws {
    while true {
      guard let count = try readByte() else {
        throw GIFLoopExtensionParserError.malformedGIF
      }
      if count == 0 { return }
      try skip(Int(count))
    }
  }
}

struct GIFMetadataInspector {
  func inspect(_ url: URL) throws -> EncodedGIF {
    var fileInfo = stat()
    guard lstat(url.path, &fileInfo) == 0,
      fileInfo.st_mode & S_IFMT == S_IFREG,
      fileInfo.st_size > 0,
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      CGImageSourceGetCount(source) > 0,
      let globalProperties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
    else { throw OriginalGIFEncodingError.invalidOutput }
    let globalGIF = globalProperties[kCGImagePropertyGIFDictionary] as? [CFString: Any] ?? [:]

    let count = CGImageSourceGetCount(source)
    var width: Int?
    var height: Int?
    var delays: [Int] = []
    for index in 0..<count {
      guard
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
          as? [CFString: Any],
        let frameWidth = properties[kCGImagePropertyPixelWidth] as? Int,
        let frameHeight = properties[kCGImagePropertyPixelHeight] as? Int,
        frameWidth > 0, frameHeight > 0,
        let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any],
        let delay = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double
          ?? gif[kCGImagePropertyGIFDelayTime] as? Double,
        delay.isFinite, delay > 0
      else { throw OriginalGIFEncodingError.invalidOutput }
      if let width, let height {
        guard frameWidth == width, frameHeight == height else {
          throw OriginalGIFEncodingError.invalidOutput
        }
      } else {
        width = frameWidth
        height = frameHeight
      }
      let centiseconds = Int((delay * 100).rounded(.toNearestOrAwayFromZero))
      guard centiseconds > 0 else { throw OriginalGIFEncodingError.invalidOutput }
      delays.append(centiseconds)
    }
    guard let width, let height else { throw OriginalGIFEncodingError.invalidOutput }
    return EncodedGIF(
      url: url,
      width: width,
      height: height,
      frameCount: count,
      delaysCentiseconds: delays,
      durationCentiseconds: delays.reduce(0, +),
      loopsForever: (globalGIF[kCGImagePropertyGIFLoopCount] as? Int) == 0,
      fileBytes: Int64(fileInfo.st_size)
    )
  }
}

protocol OriginalGIFEncoding: Sendable {
  /// run from an asynchronous caller; ImageIO work is dispatched away from the main actor.
  func encode(
    _ sequence: CapturedPNGSequence,
    to reservation: PreviewOutputReservation
  ) async throws -> EncodedGIF

  func encode(
    _ sequence: CapturedPNGSequence,
    loopMode: GIFLoopMode,
    to reservation: PreviewOutputReservation
  ) async throws -> EncodedGIF
}

extension OriginalGIFEncoding {
  func encode(
    _ sequence: CapturedPNGSequence,
    loopMode: GIFLoopMode,
    to reservation: PreviewOutputReservation
  ) async throws -> EncodedGIF {
    guard loopMode == .forever else { throw OriginalGIFEncodingError.invalidOutput }
    return try await encode(sequence, to: reservation)
  }
}

private final class GIFCancellationFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false

  func cancel() {
    lock.lock()
    value = true
    lock.unlock()
  }

  var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

private final class CappedGIFDataConsumer {
  let descriptor: Int32
  let maximumBytes: Int64
  private(set) var bytesWritten: Int64 = 0
  private(set) var exceededLimit = false
  private(set) var writeFailed = false

  init(descriptor: Int32, maximumBytes: Int64) {
    self.descriptor = descriptor
    self.maximumBytes = maximumBytes
  }

  func putBytes(_ buffer: UnsafeRawPointer, count: Int) -> Int {
    guard count >= 0,
      Int64(count) <= maximumBytes - bytesWritten
    else {
      exceededLimit = true
      return 0
    }
    var remaining = count
    var cursor = buffer
    while remaining > 0 {
      let written = Darwin.write(descriptor, cursor, remaining)
      guard written > 0 else {
        writeFailed = true
        return count - remaining
      }
      remaining -= written
      cursor = cursor.advanced(by: written)
    }
    bytesWritten += Int64(count)
    return count
  }
}

struct ImageIOOriginalGIFEncoder: OriginalGIFEncoding {
  private let frameProgress: @Sendable (Int) -> Void

  init(frameProgress: @escaping @Sendable (Int) -> Void = { _ in }) {
    self.frameProgress = frameProgress
  }

  func encode(
    _ sequence: CapturedPNGSequence,
    to reservation: PreviewOutputReservation
  ) async throws -> EncodedGIF {
    try await encode(sequence, loopMode: .forever, to: reservation)
  }

  func encode(
    _ sequence: CapturedPNGSequence,
    loopMode: GIFLoopMode,
    to reservation: PreviewOutputReservation
  ) async throws -> EncodedGIF {
    let cancellation = GIFCancellationFlag()
    return try await withTaskCancellationHandler {
      try await Task.detached(priority: .utility) {
        try encodeSynchronously(
          sequence, loopMode: loopMode, to: reservation, cancellation: cancellation)
      }.value
    } onCancel: {
      cancellation.cancel()
    }
  }

  private func encodeSynchronously(
    _ sequence: CapturedPNGSequence,
    loopMode: GIFLoopMode,
    to reservation: PreviewOutputReservation,
    cancellation: GIFCancellationFlag
  ) throws -> EncodedGIF {
    var ownsOutput = false
    do {
      try checkCancellation(cancellation)
      guard !sequence.frames.isEmpty, reservation.maximumBytes > 0,
        !FileManager.default.fileExists(atPath: reservation.url.path)
      else { throw OriginalGIFEncodingError.invalidSequence }
      let delays = try Self.frameDelaysCentiseconds(
        for: sequence.frames.map(\.timestamp), finalFrameDuration: sequence.finalFrameDuration)
      var dimensions: (width: Int, height: Int)?

      let descriptor = open(
        reservation.url.path,
        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
        S_IRUSR | S_IWUSR
      )
      guard descriptor >= 0 else { throw OriginalGIFEncodingError.destinationCreationFailed }
      defer { _ = close(descriptor) }
      ownsOutput = true

      let consumerContext = CappedGIFDataConsumer(
        descriptor: descriptor,
        maximumBytes: reservation.maximumBytes
      )
      let contextPointer = Unmanaged.passUnretained(consumerContext).toOpaque()
      defer { withExtendedLifetime(consumerContext) {} }
      var callbacks = CGDataConsumerCallbacks(
        putBytes: { info, buffer, count in
          guard let info else { return 0 }
          let context = Unmanaged<CappedGIFDataConsumer>.fromOpaque(info)
            .takeUnretainedValue()
          return context.putBytes(buffer, count: count)
        },
        releaseConsumer: nil
      )
      guard let consumer = CGDataConsumer(info: contextPointer, cbks: &callbacks) else {
        throw OriginalGIFEncodingError.destinationCreationFailed
      }
      var destinationProperties: [CFString: Any] = [:]
      if loopMode == .forever {
        destinationProperties[kCGImagePropertyGIFDictionary] = [
          kCGImagePropertyGIFLoopCount: 0
        ]
      }
      guard
        let destination = CGImageDestinationCreateWithDataConsumer(
          consumer, UTType.gif.identifier as CFString, sequence.frames.count,
          destinationProperties as CFDictionary
        )
      else { throw OriginalGIFEncodingError.destinationCreationFailed }

      for (index, frame) in sequence.frames.enumerated() {
        try checkCancellation(cancellation)
        guard let source = CGImageSourceCreateWithURL(frame.url as CFURL, nil),
          CGImageSourceGetType(source) == UTType.png.identifier as CFString,
          CGImageSourceGetCount(source) == 1,
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw OriginalGIFEncodingError.invalidFrame }
        if let dimensions {
          guard image.width == dimensions.width, image.height == dimensions.height else {
            throw OriginalGIFEncodingError.inconsistentDimensions
          }
        } else {
          dimensions = (image.width, image.height)
        }

        let delay = Double(delays[index]) / 100
        let properties: [CFString: Any] = [
          kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: delay,
            kCGImagePropertyGIFUnclampedDelayTime: delay,
          ]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        frameProgress(index + 1)
        try checkCancellation(cancellation)
        if consumerContext.exceededLimit {
          throw OriginalGIFEncodingError.outputSizeExceeded
        }
        if consumerContext.writeFailed { throw OriginalGIFEncodingError.encodingFailed }
      }

      try checkCancellation(cancellation)
      let finalized = CGImageDestinationFinalize(destination)
      if consumerContext.exceededLimit {
        throw OriginalGIFEncodingError.outputSizeExceeded
      }
      if consumerContext.writeFailed { throw OriginalGIFEncodingError.encodingFailed }
      guard finalized else {
        throw OriginalGIFEncodingError.encodingFailed
      }
      try checkOutputSize(at: reservation.url, maximumBytes: reservation.maximumBytes)
      return try validateOutput(
        at: reservation.url,
        dimensions: dimensions,
        delays: delays,
        loopMode: loopMode,
        maximumBytes: reservation.maximumBytes
      )
    } catch {
      if ownsOutput { try? FileManager.default.removeItem(at: reservation.url) }
      if cancellation.isCancelled { throw OriginalGIFEncodingError.cancelled }
      throw error
    }
  }

  static func frameDelaysCentiseconds(
    for timestamps: [TimeInterval], finalFrameDuration: TimeInterval? = nil
  ) throws -> [Int] {
    guard !timestamps.isEmpty else { throw OriginalGIFEncodingError.invalidSequence }
    guard timestamps.allSatisfy(\.isFinite), timestamps.allSatisfy({ $0 >= 0 }) else {
      throw OriginalGIFEncodingError.invalidTimestamp
    }
    let nanoseconds = try timestamps.map { timestamp -> Int64 in
      let value = timestamp * 1_000_000_000
      guard value.isFinite, value < Double(Int64.max) else {
        throw OriginalGIFEncodingError.invalidTimestamp
      }
      return Int64(value.rounded(.toNearestOrAwayFromZero))
    }
    for index in 1..<nanoseconds.count where nanoseconds[index] <= nanoseconds[index - 1] {
      throw OriginalGIFEncodingError.invalidTimestamp
    }

    let finalInterval: Int64
    if let finalFrameDuration {
      let value = finalFrameDuration * 1_000_000_000
      guard value.isFinite, value > 0, value < Double(Int64.max) else {
        throw OriginalGIFEncodingError.invalidTimestamp
      }
      finalInterval = Int64(value.rounded(.toNearestOrAwayFromZero))
    } else {
      finalInterval =
        nanoseconds.count > 1
        ? nanoseconds[nanoseconds.count - 1] - nanoseconds[nanoseconds.count - 2]
        : 41_666_667
    }
    let duration = nanoseconds[nanoseconds.count - 1] - nanoseconds[0]
    let (totalNanoseconds, overflow) = duration.addingReportingOverflow(finalInterval)
    guard !overflow else { throw OriginalGIFEncodingError.invalidTimestamp }
    var boundaries = nanoseconds.map { $0 - nanoseconds[0] }
    boundaries.append(totalNanoseconds)
    let rounded = try boundaries.map { boundary -> Int in
      let (adjusted, roundingOverflow) = boundary.addingReportingOverflow(5_000_000)
      guard !roundingOverflow else {
        throw OriginalGIFEncodingError.invalidTimestamp
      }
      return Int(adjusted / 10_000_000)
    }
    let delays = zip(rounded, rounded.dropFirst()).map { $1 - $0 }
    guard delays.allSatisfy({ $0 > 0 }) else {
      throw OriginalGIFEncodingError.unrepresentableTiming
    }
    return delays
  }

  private func checkCancellation(_ flag: GIFCancellationFlag) throws {
    if flag.isCancelled { throw OriginalGIFEncodingError.cancelled }
  }

  private func checkOutputSize(at url: URL, maximumBytes: Int64) throws {
    var info = stat()
    guard lstat(url.path, &info) == 0 else { return }
    guard info.st_mode & S_IFMT == S_IFREG else {
      throw OriginalGIFEncodingError.invalidOutput
    }
    guard Int64(info.st_size) <= maximumBytes else {
      throw OriginalGIFEncodingError.outputSizeExceeded
    }
  }

  private func containsLoopingApplicationExtension(
    at url: URL,
    maximumBytes: Int64
  ) throws -> Bool {
    let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { throw OriginalGIFEncodingError.invalidOutput }
    defer { _ = close(descriptor) }

    var initialInfo = stat()
    guard fstat(descriptor, &initialInfo) == 0,
      initialInfo.st_mode & S_IFMT == S_IFREG,
      initialInfo.st_size > 0
    else { throw OriginalGIFEncodingError.invalidOutput }
    guard initialInfo.st_size <= maximumBytes,
      let byteCount = Int(exactly: initialInfo.st_size)
    else { throw OriginalGIFEncodingError.outputSizeExceeded }
    let mapping = mmap(nil, byteCount, PROT_READ, MAP_PRIVATE, descriptor, 0)
    guard mapping != MAP_FAILED else { throw OriginalGIFEncodingError.invalidOutput }
    defer { _ = munmap(mapping, byteCount) }

    let data = UnsafeRawBufferPointer(start: mapping, count: byteCount)
    let containsLoopingExtension: Bool
    do {
      containsLoopingExtension =
        try GIFLoopExtensionParser
        .containsLoopingApplicationExtension(in: data)
    } catch {
      throw OriginalGIFEncodingError.invalidOutput
    }
    var finalInfo = stat()
    guard fstat(descriptor, &finalInfo) == 0,
      finalInfo.st_size == initialInfo.st_size
    else { throw OriginalGIFEncodingError.invalidOutput }
    return containsLoopingExtension
  }

  private func validateOutput(
    at url: URL,
    dimensions expectedDimensions: (width: Int, height: Int)?,
    delays expectedDelays: [Int],
    loopMode: GIFLoopMode,
    maximumBytes: Int64
  ) throws -> EncodedGIF {
    try checkOutputSize(at: url, maximumBytes: maximumBytes)
    guard let expectedDimensions else {
      throw OriginalGIFEncodingError.invalidOutput
    }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      throw OriginalGIFEncodingError.invalidOutput
    }
    let sourceFrameCount = CGImageSourceGetCount(source)
    guard sourceFrameCount == expectedDelays.count else {
      throw OriginalGIFEncodingError.invalidOutput
    }
    guard let globalProperties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
    else {
      throw OriginalGIFEncodingError.invalidOutput
    }
    let gifProperties =
      globalProperties[kCGImagePropertyGIFDictionary] as? [CFString: Any] ?? [:]
    let loopCount = gifProperties[kCGImagePropertyGIFLoopCount] as? Int
    let containsLoopingExtension = try containsLoopingApplicationExtension(
      at: url,
      maximumBytes: maximumBytes
    )
    let hasValidLoopMetadata: Bool
    switch loopMode {
    case .forever:
      hasValidLoopMetadata = loopCount == 0 && containsLoopingExtension
    case .once:
      hasValidLoopMetadata = (loopCount == nil || loopCount == 1) && !containsLoopingExtension
    }
    guard hasValidLoopMetadata else {
      throw OriginalGIFEncodingError.invalidOutput
    }

    var actualDelays: [Int] = []
    for index in 0..<expectedDelays.count {
      guard
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
          as? [CFString: Any]
      else {
        throw OriginalGIFEncodingError.invalidOutput
      }
      let width = properties[kCGImagePropertyPixelWidth] as? Int
      let height = properties[kCGImagePropertyPixelHeight] as? Int
      let frameGIF = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
      let delay =
        frameGIF?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        ?? frameGIF?[kCGImagePropertyGIFDelayTime] as? Double
      guard width == expectedDimensions.width, height == expectedDimensions.height,
        let delay, delay.isFinite
      else {
        throw OriginalGIFEncodingError.invalidOutput
      }
      actualDelays.append(Int((delay * 100).rounded(.toNearestOrAwayFromZero)))
    }
    guard actualDelays == expectedDelays else {
      throw OriginalGIFEncodingError.invalidOutput
    }
    try checkOutputSize(at: url, maximumBytes: maximumBytes)
    var info = stat()
    let fileStatus = lstat(url.path, &info)
    guard fileStatus == 0, info.st_size > 0 else {
      throw OriginalGIFEncodingError.invalidOutput
    }
    return EncodedGIF(
      url: url,
      width: expectedDimensions.width,
      height: expectedDimensions.height,
      frameCount: actualDelays.count,
      delaysCentiseconds: actualDelays,
      durationCentiseconds: actualDelays.reduce(0, +),
      loopsForever: loopMode == .forever,
      fileBytes: Int64(info.st_size)
    )
  }
}
