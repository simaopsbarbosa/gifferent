import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

enum RecordingStreamError: Error, Equatable {
  case displayUnavailable
  case windowUnavailable
  case invalidRegion
  case invalidDimensions
}

/// this prototype owns only capture and frame delivery; encoding consumes `transport.frames`.
@MainActor
final class ScreenCaptureRecordingStream {
  let transport: RecordingFrameTransport

  private let stream: SCStream
  private let output: ScreenFrameOutput
  private let target: RecordingTarget
  private let sourceService: CaptureSourceService
  private let onStop: @MainActor (CaptureTerminationReason) -> Void
  private var monitorTask: Task<Void, Never>?
  private var stopped = false

  private init(
    stream: SCStream,
    output: ScreenFrameOutput,
    target: RecordingTarget,
    sourceService: CaptureSourceService,
    transport: RecordingFrameTransport,
    onStop: @escaping @MainActor (CaptureTerminationReason) -> Void
  ) {
    self.stream = stream
    self.output = output
    self.target = target
    self.sourceService = sourceService
    self.transport = transport
    self.onStop = onStop
  }

  static func start(
    target: RecordingTarget,
    showsCursor: Bool,
    sourceService: CaptureSourceService = CaptureSourceService(),
    onStop: @escaping @MainActor (CaptureTerminationReason) -> Void
  ) async throws -> ScreenCaptureRecordingStream {
    guard sourceService.authorizationStatus() == .granted else {
      throw CaptureSourceError.permissionRequired
    }
    let content = try await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: true)
    let filter = try makeFilter(target: target, content: content)
    let configuration = try makeConfiguration(
      target: target, filter: filter, showsCursor: showsCursor)
    let transport = RecordingFrameTransport()
    let output = ScreenFrameOutput(transport: transport)
    let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
    try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.sampleQueue)

    let session = ScreenCaptureRecordingStream(
      stream: stream,
      output: output,
      target: target,
      sourceService: sourceService,
      transport: transport,
      onStop: onStop
    )
    output.onStreamFailure = { [weak session] in
      Task { @MainActor in
        await session?.stop(reason: .streamFailed)
      }
    }
    do {
      try await stream.startCapture()
    } catch {
      transport.finish()
      throw error
    }
    session.startMonitoring()
    return session
  }

  func stop(reason: CaptureTerminationReason = .userStopped) async {
    guard !stopped else { return }
    stopped = true
    monitorTask?.cancel()
    monitorTask = nil
    do {
      try await stream.stopCapture()
    } catch {
      // a failed stop still closes the local frame handoff.
    }
    transport.finish()
    onStop(reason)
  }

  private func startMonitoring() {
    monitorTask = Task { [weak self] in
      var consecutiveListingFailures = 0
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(500))
        guard let self, !Task.isCancelled else { return }
        do {
          let inventory = try await self.sourceService.availableSources()
          consecutiveListingFailures = 0
          let snapshot = RecordingTargetSnapshot(
            displayIDs: Set(inventory.displays.map(\.id)),
            visibleWindowIDs: Set(inventory.windows.map(\.id))
          )
          if let reason = RecordingTargetMonitor.lossReason(for: self.target, in: snapshot) {
            await self.stop(reason: reason)
            return
          }
        } catch CaptureSourceError.permissionRequired {
          await self.stop(reason: .permissionLost)
          return
        } catch {
          consecutiveListingFailures += 1
          if consecutiveListingFailures >= 3 {
            await self.stop(reason: .streamFailed)
            return
          }
        }
      }
    }
  }

  private static func makeFilter(
    target: RecordingTarget,
    content: SCShareableContent
  ) throws -> SCContentFilter {
    switch target {
    case .display(let id), .region(let id, _):
      guard let display = content.displays.first(where: { $0.displayID == id }) else {
        throw RecordingStreamError.displayUnavailable
      }
      let ownApplication = content.applications.filter {
        $0.bundleIdentifier == Bundle.main.bundleIdentifier
      }
      return SCContentFilter(
        display: display, excludingApplications: ownApplication, exceptingWindows: [])
    case .window(let id):
      guard let window = content.windows.first(where: { $0.windowID == id }) else {
        throw RecordingStreamError.windowUnavailable
      }
      return SCContentFilter(desktopIndependentWindow: window)
    }
  }

  private static func makeConfiguration(
    target: RecordingTarget,
    filter: SCContentFilter,
    showsCursor: Bool
  ) throws -> SCStreamConfiguration {
    let sourceRect: CGRect
    switch target {
    case .region(_, let rect):
      guard rect.origin.x.isFinite, rect.origin.y.isFinite,
        rect.width.isFinite, rect.height.isFinite,
        rect.width > 0, rect.height > 0,
        CGRect(origin: .zero, size: filter.contentRect.size).contains(rect)
      else { throw RecordingStreamError.invalidRegion }
      sourceRect = rect
    case .display, .window:
      sourceRect = CGRect(origin: .zero, size: filter.contentRect.size)
    }

    let scale = CGFloat(filter.pointPixelScale)
    let pixelWidth = (sourceRect.width * scale).rounded(.up)
    let pixelHeight = (sourceRect.height * scale).rounded(.up)
    guard pixelWidth.isFinite, pixelHeight.isFinite,
      pixelWidth > 0, pixelHeight > 0,
      pixelWidth <= CGFloat(Int.max), pixelHeight <= CGFloat(Int.max)
    else { throw RecordingStreamError.invalidDimensions }

    let configuration = SCStreamConfiguration()
    configuration.width = Int(pixelWidth)
    configuration.height = Int(pixelHeight)
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: 24)
    configuration.pixelFormat = kCVPixelFormatType_32BGRA
    configuration.queueDepth = 3
    configuration.showsCursor = showsCursor
    configuration.capturesAudio = false
    configuration.scalesToFit = false
    if case .region = target {
      configuration.sourceRect = sourceRect
    }
    return configuration
  }
}

private final class ScreenFrameOutput: NSObject, SCStreamOutput, SCStreamDelegate,
  @unchecked Sendable
{
  let sampleQueue = DispatchQueue(label: "gifferent.recording.samples", qos: .userInitiated)
  var onStreamFailure: (@Sendable () -> Void)?
  private let transport: RecordingFrameTransport

  init(transport: RecordingFrameTransport) {
    self.transport = transport
  }

  func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard type == .screen,
      let attachments = CMSampleBufferGetSampleAttachmentsArray(
        sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
      let statusValue = attachments.first?[.status] as? Int,
      let status = SCFrameStatus(rawValue: statusValue),
      status == .complete,
      let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
    else { return }

    let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    guard time.isValid else { return }
    let nanoseconds = CMTimeConvertScale(
      time, timescale: 1_000_000_000,
      method: .roundTowardZero
    ).value
    guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else { return }
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let (byteCount, overflow) = bytesPerRow.multipliedReportingOverflow(by: height)
    guard !overflow, byteCount > 0 else { return }
    transport.offer(
      RecordingFrame(
        timestampNanoseconds: nanoseconds,
        width: width,
        height: height,
        bytesPerRow: bytesPerRow,
        bgra: Data(bytes: base, count: byteCount)
      ))
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    onStreamFailure?()
  }
}
