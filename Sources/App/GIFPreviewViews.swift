import AppKit
import ImageIO
import SwiftUI

@MainActor
private func updateCoordinatorAfterViewUpdate(_ update: @escaping @MainActor () async -> Void) {
  Task { @MainActor in
    await Task.yield()
    await update()
  }
}

@MainActor
struct GIFPreviewReadyView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ObservedObject var runtime: GifferentRuntime
  @ObservedObject var coordinator: RecordingCoordinator
  let snapshot: RecordingSessionSnapshot
  let gif: EncodedGIF
  let previewWidth: CGFloat
  @State private var inspectedFrame: URL?
  @State private var trimDraftActive = false

  private var displayedGIF: EncodedGIF {
    coordinator.displayedPreviewGIF ?? gif
  }

  private var fittedGIFSize: CGSize {
    let width = CGFloat(displayedGIF.width)
    let height = CGFloat(displayedGIF.height)
    guard width > 0, height > 0, previewWidth > 0 else { return .zero }
    let scale = min(previewWidth / width, 280 / height)
    return CGSize(width: width * scale, height: height * scale)
  }

  var body: some View {
    VStack(spacing: 9) {
      Group {
        if let inspectedFrame, let image = NSImage(contentsOf: inspectedFrame) {
          Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
        } else {
          AnimatedGIFView(url: displayedGIF.url)
        }
      }
      .frame(
        width: previewWidth,
        height: 280
      )
      .background { PreviewDitherBackground() }
      .overlay {
        Rectangle()
          .strokeBorder(.quaternary, lineWidth: 1)
          .frame(width: fittedGIFSize.width, height: fittedGIFSize.height)
          .shadow(color: .black.opacity(0.35), radius: 6, x: -3)
          .shadow(color: .black.opacity(0.35), radius: 6, x: 3)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
      .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .strokeBorder(.quaternary, lineWidth: 1)
      }
      .overlay {
        if coordinator.isPreviewUpdateInProgress || coordinator.isCompressionInProgress {
          VStack(spacing: 9) {
            ProgressView()
              .controlSize(.small)
              .accessibilityLabel("updating gif")
            Text("updating gif")
              .font(.callout.weight(.medium))
            if coordinator.isCompressionInProgress {
              Button("cancel") { Task { await coordinator.cancelCompression() } }
                .controlSize(.small)
                .accessibilityIdentifier("cancel-compression-button")
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(.ultraThinMaterial)
          .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
          .accessibilityElement(children: .contain)
          .accessibilityIdentifier("preview-processing-overlay")
          .transition(.opacity)
        }
      }
      .animation(
        reduceMotion ? nil : .easeInOut(duration: 0.16),
        value: coordinator.isPreviewUpdateInProgress
      )
      .animation(
        reduceMotion ? nil : .easeInOut(duration: 0.16),
        value: coordinator.isCompressionInProgress
      )
      .frame(maxWidth: .infinity)

      GIFEditControls(
        coordinator: coordinator, inspectedFrame: $inspectedFrame, trimDraftActive: $trimDraftActive
      )
      .disabled(
        coordinator.isCompressionInProgress || coordinator.isQualityCompressionScheduled
          || coordinator.compressedPreview != nil
      )
      GIFCompressionControls(coordinator: coordinator)
        .padding(.top, 6)

      HStack(spacing: 28) {
        metadata(
          "file size",
          value: ByteCountFormatter.string(
            fromByteCount: displayedGIF.fileBytes, countStyle: .file),
          id: "preview-size"
        )
        metadata(
          "duration", value: duration(displayedGIF.durationCentiseconds), id: "preview-duration")
        metadata(
          "dimensions", value: "\(displayedGIF.width) by \(displayedGIF.height)",
          id: "preview-dimensions")
      }
      .frame(maxWidth: .infinity)

      if snapshot.isPartialResult {
        Text("partial recording")
          .accessibilityIdentifier("preview-partial-status")
      }

      HStack(spacing: 8) {
        if coordinator.compressedPreview != nil {
          Button {
            Task {
              if coordinator.isCompressionInProgress {
                await coordinator.cancelCompression()
              }
              await coordinator.backToOriginalPreview()
            }
          } label: {
            Image(systemName: "arrow.left")
          }
          .buttonStyle(.bordered)
          .accessibilityLabel("back to original")
          .help("back to original")
          .accessibilityIdentifier("back-to-original-button")
        }
        Button("copy (⌘C)") { runtime.copyPreview() }
          .keyboardShortcut("c", modifiers: .command)
          .disabled(exportIsDisabled)
          .accessibilityIdentifier("copy-preview-button")
        Button("save… (⌘S)") { runtime.savePreview() }
          .keyboardShortcut("s", modifiers: .command)
          .disabled(exportIsDisabled)
          .accessibilityIdentifier("save-preview-button")
        Button("close") { runtime.requestPreviewClose() }
          .accessibilityIdentifier("close-preview-button")
      }
      .frame(maxWidth: .infinity)
    }
    .background {
      Text("preview ready")
        .accessibilityIdentifier("preview-status")
        .accessibilityValue("preview ready")
        .frame(width: 1, height: 1)
        .opacity(0.01)
        .accessibilityHidden(false)
    }
    .overlay(alignment: .top) {
      GIFPreviewActionNotice(
        action: coordinator.previewAction,
        sizeSearchUnavailable: GIFSizeSearchPlan(settings: coordinator.compressionSettings)
          .candidates.isEmpty
      )
      .id(coordinator.previewFeedbackRevision)
      .padding(.top, 8)
    }
  }

  private var exportIsDisabled: Bool {
    trimDraftActive || coordinator.previewAction == .copying || coordinator.previewAction == .saving
      || coordinator.isPreviewUpdateInProgress || coordinator.isCompressionInProgress
      || coordinator.isQualityCompressionScheduled
  }

  private func metadata(_ label: String, value: String, id: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label).font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
      Text(value)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityIdentifier(id)
    }
    .accessibilityElement(children: .contain)
    .padding(.vertical, 12)
  }

  private func duration(_ centiseconds: Int) -> String {
    let seconds = Double(centiseconds) / 100
    return String(format: "%.2f seconds", seconds)
  }
}

private struct PreviewDitherBackground: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme
  @State private var canAnimate = false

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: reduceMotion || !canAnimate)) {
      timeline in
      PreviewDitherCanvas(
        time: reduceMotion || !canAnimate ? 0 : timeline.date.timeIntervalSinceReferenceDate,
        dark: colorScheme == .dark
      )
    }
    .background(Color(nsColor: .controlBackgroundColor))
    .background { PreviewAnimationVisibility(canAnimate: $canAnimate) }
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }
}

private struct PreviewDitherCanvas: View {
  let time: TimeInterval
  let dark: Bool

  var body: some View {
    Canvas { context, size in
      if let image = PreviewDitherArtwork.image(size: size, time: time, dark: dark) {
        context.draw(
          Image(decorative: image, scale: 1, orientation: .up).interpolation(.none),
          in: CGRect(origin: .zero, size: size)
        )
      }
    }
  }
}

enum PreviewDitherArtwork {
  private static let bayer = [
    0, 32, 8, 40, 2, 34, 10, 42,
    48, 16, 56, 24, 50, 18, 58, 26,
    12, 44, 4, 36, 14, 46, 6, 38,
    60, 28, 52, 20, 62, 30, 54, 22,
    3, 35, 11, 43, 1, 33, 9, 41,
    51, 19, 59, 27, 49, 17, 57, 25,
    15, 47, 7, 39, 13, 45, 5, 37,
    63, 31, 55, 23, 61, 29, 53, 21,
  ]

  static func image(size: CGSize, time: TimeInterval, dark: Bool) -> CGImage? {
    guard size.width > 0, size.height > 0 else { return nil }
    let width = max(1, min(256, Int(size.width / 3)))
    let height = max(1, min(128, Int(size.height / 3)))
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let base: UInt8 = dark ? 27 : 216
    let highlight: UInt8 = dark ? 37 : 201

    for y in 0..<height {
      let vertical = Double(y) / Double(height)
      let centers = (0..<8).map { vine in
        let phase = Double(vine) * 2.1
        return Double(width) * (0.06 + Double(vine) * 0.125)
          + Double(width) * 0.075 * sin(vertical * 7 + phase + time * 0.10)
          + Double(width) * 0.035 * sin(vertical * 15 - phase + time * 0.07)
      }
      for x in 0..<width {
        var nearest = Double.greatestFiniteMagnitude
        for center in centers {
          nearest = min(nearest, abs(Double(x) - center))
        }
        let distance = nearest / max(1, Double(width) * 0.014)
        let intensity = 0.8 / (1 + distance * distance)
        let threshold = (Double(bayer[(y % 8) * 8 + x % 8]) + 0.5) / 64
        let value = intensity > threshold ? highlight : base
        let offset = (y * width + x) * 4
        pixels[offset] = value
        pixels[offset + 1] = value
        pixels[offset + 2] = value
        pixels[offset + 3] = 255
      }
    }

    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
    )
  }
}

private struct PreviewAnimationVisibility: NSViewRepresentable {
  @Binding var canAnimate: Bool

  func makeNSView(context: Context) -> VisibilityView {
    let view = VisibilityView()
    view.onChange = { value in
      DispatchQueue.main.async { canAnimate = value }
    }
    return view
  }

  func updateNSView(_ view: VisibilityView, context: Context) {}

  final class VisibilityView: NSView {
    var onChange: ((Bool) -> Void)?
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      NotificationCenter.default.removeObserver(self)
      if let window {
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification] {
          NotificationCenter.default.addObserver(
            self, selector: #selector(updateVisibility), name: name, object: window)
        }
        NotificationCenter.default.addObserver(
          self, selector: #selector(updateVisibility), name: .NSProcessInfoPowerStateDidChange,
          object: nil)
      }
      updateVisibility()
    }

    @objc private func updateVisibility() {
      onChange?(
        window?.occlusionState.contains(.visible) == true
          && !ProcessInfo.processInfo.isLowPowerModeEnabled
      )
    }
  }
}

@MainActor
private struct GIFPreviewActionNotice: View {
  let action: PreviewAction
  let sizeSearchUnavailable: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isVisible = false
  @State private var showsSizeSearchNotice = false

  private var message: String {
    if showsSizeSearchNotice {
      return "automatic size search is unavailable at this resolution or fps"
    }
    return switch action {
    case .copied: "copied"
    case .saved: "saved"
    case .cancelled: "save cancelled"
    case .updateFailed: "could not update gif; previous preview kept"
    case .failed: "could not export gif; try again"
    case .idle, .updated, .copying, .saving: ""
    }
  }

  var body: some View {
    ZStack {
      if isVisible, !message.isEmpty {
        Text(message)
          .font(.callout)
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background(.regularMaterial, in: Capsule())
          .overlay { Capsule().strokeBorder(.quaternary, lineWidth: 1) }
          .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
          .accessibilityIdentifier(
            showsSizeSearchNotice ? "compression-search-unavailable" : "preview-action-status"
          )
          .accessibilityValue(message)
          .accessibilityAddTraits(.updatesFrequently)
          .transition(.opacity)
      }
    }
    .allowsHitTesting(false)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isVisible)
    .onAppear {
      showsSizeSearchNotice = sizeSearchUnavailable && (action == .idle || action == .updated)
    }
    .onChange(of: sizeSearchUnavailable) { _, unavailable in
      showsSizeSearchNotice = unavailable
    }
    .onChange(of: action) { _, value in
      if value != .updated && value != .idle { showsSizeSearchNotice = false }
    }
    .task(id: message) {
      isVisible = !message.isEmpty
      guard isVisible else { return }
      do {
        try await Task.sleep(for: .seconds(action == .failed || action == .updateFailed ? 6 : 2.5))
        isVisible = false
      } catch {
        // a newer action or a closed preview cancels this notice's timer.
      }
    }
  }
}

@MainActor
private struct GIFEditControls: View {
  @ObservedObject var coordinator: RecordingCoordinator
  @Binding var inspectedFrame: URL?
  @Binding var trimDraftActive: Bool

  var body: some View {
    Group {
      if let parameters = coordinator.editParameters, coordinator.editFrameCount > 0 {
        VStack(alignment: .leading, spacing: 4) {
          Text("trim")
            .font(.caption)
            .foregroundStyle(.secondary)
          GIFTimelineControl(
            sequence: coordinator.trimSource,
            frameCount: coordinator.editFrameCount,
            startIndex: parameters.frameRange.startIndex,
            endIndexExclusive: parameters.frameRange.endIndexExclusive,
            inspectedFrame: $inspectedFrame,
            trimDraftActive: $trimDraftActive,
            onChange: updateTrim
          )

          HStack(spacing: 8) {
            Text("speed")
            Picker(
              "playback speed",
              selection: Binding(
                get: { parameters.playbackSpeed },
                set: { value in
                  updateCoordinatorAfterViewUpdate { coordinator.updatePlaybackSpeed(value) }
                }
              )
            ) {
              ForEach(GIFEditParameters.speedPresets, id: \.self) { speed in
                Text("\(speed.formatted(.number.precision(.fractionLength(0...2))))×").tag(speed)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityIdentifier("playback-speed-picker")
            Spacer(minLength: 0)
            Text("fps")
            Picker(
              "output frame rate",
              selection: Binding(
                get: { parameters.frameRate },
                set: { value in
                  updateCoordinatorAfterViewUpdate { coordinator.updateFrameRate(value) }
                }
              )
            ) {
              ForEach(GIFCompressionFrameRate.exportPresets) { rate in
                Text(rate.label).tag(rate)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityIdentifier("output-frame-rate-picker")
            Spacer(minLength: 0)
            Text("loop")
            Picker(
              "loop",
              selection: Binding(
                get: { parameters.loopMode },
                set: { value in
                  updateCoordinatorAfterViewUpdate {
                    coordinator.updateLoopMode(value)
                  }
                }
              )
            ) {
              Text("forever")
                .tag(GIFLoopMode.forever)
                .accessibilityIdentifier("loop-forever-button")
              Text("once")
                .tag(GIFLoopMode.once)
                .accessibilityIdentifier("loop-once-button")
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityIdentifier("loop-mode-picker")
          }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(coordinator.isPreviewActionInProgress)

      }
    }
  }

  private func updateTrim(start: Int, end: Int) {
    updateCoordinatorAfterViewUpdate {
      coordinator.updateTrim(startIndex: start, endIndexExclusive: end)
    }
  }

}

@MainActor
private struct GIFCompressionControls: View {
  @ObservedObject var coordinator: RecordingCoordinator

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("compression")
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack(spacing: 8) {
        Text("size")
        GIFCompressionScaleControl(coordinator: coordinator)
        Spacer(minLength: 8)
        GIFCompressionDestinationControl(coordinator: coordinator)
      }
      .frame(maxWidth: .infinity)
      GIFCompressionQualityControl(coordinator: coordinator)
      GIFCompressionActionControl(coordinator: coordinator)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

@MainActor
private struct GIFCompressionDestinationControl: View {
  @ObservedObject var coordinator: RecordingCoordinator

  private var hasApprovedCandidates: Bool {
    !GIFSizeSearchPlan(settings: coordinator.compressionSettings).candidates.isEmpty
  }

  var body: some View {
    Menu {
      ForEach(GIFCompressionDestination.allCases) { destination in
        Button {
          coordinator.startSizeSearch(for: destination)
        } label: {
          Text("\(destination.displayName) (\(destination.publishedMaximumLabel) max)")
        }
        .disabled(
          coordinator.isPreviewActionInProgress || coordinator.isQualityCompressionScheduled
            || coordinator.compressedPreview != nil
            || !hasApprovedCandidates
        )
        .accessibilityIdentifier("compression-destination-\(destination.accessibilityID)")
        .help(destinationHelp(for: destination))
      }
    } label: {
      Text("compress for")
    }
    .disabled(
      coordinator.isPreviewActionInProgress || coordinator.isQualityCompressionScheduled
        || coordinator.compressedPreview != nil
        || !hasApprovedCandidates
    )
    .accessibilityIdentifier("compression-destination-menu")
    .help(
      hasApprovedCandidates
        ? "choose a destination and start size optimization"
        : "automatic size search is unavailable at this resolution or fps")
  }

  private func destinationHelp(for destination: GIFCompressionDestination) -> String {
    let scope = destination.limitScopeDescription
    return "target: \(destination.targetLabel) · maximum: "
      + "\(destination.publishedMaximumLabel) · \(scope) · checked "
      + destination.limitResearchDate
  }
}

@MainActor
private struct GIFCompressionScaleControl: View {
  @ObservedObject var coordinator: RecordingCoordinator
  @State private var selectedScale = GIFCompressionScale.original

  var body: some View {
    HStack(spacing: 6) {
      Picker(
        "size",
        selection: Binding(
          get: { selectedScale },
          set: { selectedScale = $0 }
        )
      ) {
        ForEach(GIFCompressionScale.allCases) { scale in
          Text(scale.label).tag(scale)
        }
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .accessibilityIdentifier("compression-scale-picker")
      .disabled(coordinator.isCompressionSettingEditDisabled)
    }
    .onAppear {
      selectedScale = coordinator.compressionSettings.scale
    }
    .onChange(of: selectedScale) { _, value in
      guard value != coordinator.compressionSettings.scale else { return }
      updateCoordinatorAfterViewUpdate {
        let started = await coordinator.compressImmediately(scale: value)
        if !started {
          selectedScale = coordinator.compressionSettings.scale
        }
      }
    }
    .onChange(of: coordinator.compressionSettings.scale) { _, value in
      selectedScale = value
    }
  }
}

@MainActor
private struct GIFCompressionQualityControl: View {
  @ObservedObject var coordinator: RecordingCoordinator
  @State private var qualityPercent = 100
  @State private var isScrubbing = false

  var body: some View {
    HStack(spacing: 8) {
      Text("quality")
      Slider(
        value: Binding(
          get: { Double(qualityPercent) },
          set: { qualityPercent = Int($0.rounded()) }
        ),
        in: 1...100,
        step: 1,
        onEditingChanged: { editing in
          isScrubbing = editing
          let quality = qualityPercent
          updateCoordinatorAfterViewUpdate {
            if editing {
              coordinator.beginQualityAdjustment()
            } else {
              coordinator.finishQualityAdjustment(quality)
            }
          }
        }
      )
      .accessibilityLabel("gifski quality")
      .accessibilityIdentifier("compression-quality-slider")
      .overlay(alignment: .center) {
        HStack(spacing: 0) {
          ForEach(0..<25, id: \.self) { _ in
            Rectangle().fill(.secondary.opacity(0.35)).frame(width: 1, height: 3)
            Spacer(minLength: 0)
          }
        }
        .allowsHitTesting(false)
        .padding(.horizontal, 7)
      }
      Text("\(qualityPercent)")
        .accessibilityIdentifier("compression-quality-value")
    }
    .disabled(coordinator.isCompressionSettingEditDisabled)
    .onAppear {
      qualityPercent = coordinator.compressionSettings.qualityPercent
    }
    .onChange(of: qualityPercent) { _, value in
      guard !isScrubbing else { return }
      updateCoordinatorAfterViewUpdate {
        coordinator.finishQualityAdjustment(value)
      }
    }
    .onChange(of: coordinator.compressionSettings.qualityPercent) { _, value in
      qualityPercent = value
    }
    .onChange(of: coordinator.isQualityCompressionScheduled) { _, scheduled in
      if !scheduled { qualityPercent = coordinator.compressionSettings.qualityPercent }
    }
  }
}

@MainActor
private struct GIFCompressionActionControl: View {
  @ObservedObject var coordinator: RecordingCoordinator

  var body: some View {
    Group {
      if !coordinator.isCompressionAvailable {
        Text("compression unavailable until a verified local backend is provided")
          .font(.caption)
          .accessibilityIdentifier("compression-unavailable-status")
      }

      switch coordinator.compressionAction {
      case .failed:
        Text("could not compress gif; previous preview kept")
          .accessibilityIdentifier("compression-action-status")
      case .cancelled:
        Text("compression cancelled; previous preview kept")
          .accessibilityIdentifier("compression-action-status")
      case .unavailable, .idle, .compressing, .compressed:
        EmptyView()
      }
    }
  }
}

@MainActor
private struct GIFTimelineControl: View {
  let sequence: CapturedPNGSequence?
  let frameCount: Int
  let startIndex: Int
  let endIndexExclusive: Int
  @Binding var inspectedFrame: URL?
  @Binding var trimDraftActive: Bool
  let onChange: @MainActor (Int, Int) -> Void
  @State private var draftStart: Int?
  @State private var draftEnd: Int?
  @State private var thumbnails: [NSImage] = []

  private var boundaries: [Double] { GIFTrimTimeline.boundaries(for: sequence) }

  var body: some View {
    GeometryReader { geometry in
      let width = max(1, geometry.size.width - 20)
      let start = min(max(draftStart ?? startIndex, 0), max(0, frameCount - 1))
      let end = min(max(draftEnd ?? endIndexExclusive, start + 1), frameCount)
      let left = 10 + width * boundaries[start]
      let right = 10 + width * boundaries[end]
      ZStack(alignment: .leading) {
        HStack(spacing: 0) {
          ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, image in
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
              .frame(width: width / CGFloat(max(1, thumbnails.count)), height: 48).clipped()
          }
        }
        .frame(width: width, height: 48).background(.quaternary).offset(x: 10)
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0, coordinateSpace: .named("trim"))
            .onChanged { value in
              inspect(nearest(value.location.x, width: width, lower: 0, upper: frameCount - 1))
            }
            .onEnded { _ in inspectedFrame = nil })
        Rectangle().fill(.black.opacity(0.55)).frame(width: max(0, left - 10), height: 48).offset(
          x: 10
        ).allowsHitTesting(false)
        Rectangle().fill(.black.opacity(0.55)).frame(width: max(0, width + 10 - right), height: 48)
          .offset(x: right).allowsHitTesting(false)
        RoundedRectangle(cornerRadius: 4).strokeBorder(.yellow, lineWidth: 4)
          .frame(width: max(1, right - left), height: 52).offset(x: left).allowsHitTesting(false)
        handle(start, x: left, width: width, isStart: true, start: start, end: end)
        handle(end, x: right, width: width, isStart: false, start: start, end: end)
      }
      .coordinateSpace(name: "trim")
    }
    .frame(height: 52)
    .task(id: sequence?.frames.first?.url) { await loadThumbnails() }
    .onDisappear {
      inspectedFrame = nil
      trimDraftActive = false
    }
  }

  private func handle(_ index: Int, x: CGFloat, width: CGFloat, isStart: Bool, start: Int, end: Int)
    -> some View
  {
    RoundedRectangle(cornerRadius: 3).fill(.yellow).frame(width: 12, height: 52)
      .overlay { Capsule().fill(.black).frame(width: 2, height: 20) }
      .position(x: x, y: 26)
      .gesture(
        DragGesture(minimumDistance: 0, coordinateSpace: .named("trim"))
          .onChanged { value in
            trimDraftActive = true
            let position = nearest(
              value.location.x, width: width, lower: isStart ? 0 : start + 1,
              upper: isStart ? end - 1 : frameCount)
            if isStart { draftStart = position } else { draftEnd = position }
            inspect(isStart ? position : position - 1)
          }
          .onEnded { _ in
            let selectedStart = draftStart ?? startIndex
            let selectedEnd = draftEnd ?? endIndexExclusive
            onChange(selectedStart, selectedEnd)
            draftStart = nil
            draftEnd = nil
            inspectedFrame = nil
            trimDraftActive = false
          }
      )
      .accessibilityLabel(isStart ? "trim start" : "trim end")
      .accessibilityIdentifier(isStart ? "trim-start-handle" : "trim-end-handle")
      .accessibilityValue("frame \(isStart ? index + 1 : index) of \(frameCount)")
      .accessibilityAdjustableAction { direction in
        let delta = direction == .increment ? 1 : -1
        if isStart {
          onChange(min(max(index + delta, 0), end - 1), end)
        } else {
          onChange(start, min(max(index + delta, start + 1), frameCount))
        }
      }
  }

  private func nearest(_ x: CGFloat, width: CGFloat, lower: Int, upper: Int) -> Int {
    GIFTrimTimeline.nearestBoundary(
      to: (x - 10) / width, boundaries: boundaries, lower: lower, upper: upper)
  }

  private func inspect(_ index: Int) {
    guard let sequence, sequence.frames.indices.contains(index) else { return }
    inspectedFrame = sequence.frames[index].url
  }

  private func loadThumbnails() async {
    guard let sequence, !sequence.frames.isEmpty else { return }
    let count = min(16, sequence.frames.count)
    let urls = (0..<count).map {
      sequence.frames[min(sequence.frames.count - 1, $0 * sequence.frames.count / count)].url
    }
    let images = await Task.detached(priority: .utility) {
      urls.compactMap { url -> CGImage? in
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceThumbnailMaxPixelSize: 120,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
      }
    }.value
    guard !Task.isCancelled else { return }
    thumbnails = images.map { NSImage(cgImage: $0, size: .zero) }
  }
}

@MainActor
private struct AnimatedGIFView: NSViewRepresentable {
  let url: URL

  func makeNSView(context: Context) -> BoundedGIFImageView {
    let view = BoundedGIFImageView()
    view.imageScaling = .scaleProportionallyUpOrDown
    view.animates = true
    view.setAccessibilityElement(true)
    view.setAccessibilityRole(.image)
    view.setAccessibilityIdentifier("animated-gif-preview")
    view.setAccessibilityLabel("animated gif preview")
    view.image = NSImage(contentsOf: url)
    context.coordinator.url = url
    return view
  }

  func updateNSView(_ view: BoundedGIFImageView, context: Context) {
    guard context.coordinator.url != url else { return }
    view.image = NSImage(contentsOf: url)
    view.animates = true
    context.coordinator.url = url
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(url: url)
  }

  final class Coordinator {
    var url: URL

    init(url: URL) {
      self.url = url
    }
  }
}

private final class BoundedGIFImageView: NSImageView {
  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
  }
}
