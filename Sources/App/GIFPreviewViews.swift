import AppKit
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

  private var displayedGIF: EncodedGIF {
    coordinator.displayedPreviewGIF ?? gif
  }

  var body: some View {
    VStack(spacing: 9) {
      AnimatedGIFView(url: displayedGIF.url)
        .frame(
          width: previewWidth,
          height: 280
        )
        .background(Color(nsColor: .controlBackgroundColor))
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

      GIFEditControls(coordinator: coordinator)
        .disabled(
          coordinator.isCompressionInProgress || coordinator.isQualityCompressionScheduled
            || coordinator.compressedPreview != nil
        )
      GIFCompressionControls(coordinator: coordinator)

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
      .padding(.top, 8)
    }
  }

  private var exportIsDisabled: Bool {
    coordinator.previewAction == .copying || coordinator.previewAction == .saving
      || coordinator.isPreviewUpdateInProgress || coordinator.isCompressionInProgress
      || coordinator.isQualityCompressionScheduled
  }

  private func metadata(_ label: String, value: String, id: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      Text(value).accessibilityIdentifier(id).accessibilityValue(value)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(label)
    .accessibilityValue(value)
    .padding(.vertical, 12)
  }

  private func duration(_ centiseconds: Int) -> String {
    let seconds = Double(centiseconds) / 100
    return String(format: "%.2f seconds", seconds)
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
      return "automatic size search is unavailable at this resolution"
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
    .onChange(of: sizeSearchUnavailable) { _, unavailable in
      showsSizeSearchNotice = unavailable
    }
    .onChange(of: action) { _, _ in
      showsSizeSearchNotice = false
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
  @State private var playbackSpeed = 1.0

  var body: some View {
    Group {
      if let parameters = coordinator.editParameters, coordinator.editFrameCount > 0 {
        VStack(alignment: .leading, spacing: 4) {
          Text("trim")
            .font(.caption)
            .foregroundStyle(.secondary)
          GIFTimelineControl(
            frameCount: coordinator.editFrameCount,
            startIndex: parameters.frameRange.startIndex,
            endIndexExclusive: parameters.frameRange.endIndexExclusive,
            onChange: updateTrim
          )

          HStack(spacing: 8) {
            Text("speed")
            Slider(
              value: $playbackSpeed,
              in: 0.5...2,
              step: 0.1
            )
            .accessibilityLabel("playback speed")
            .accessibilityIdentifier("playback-speed-slider")
            .onChange(of: playbackSpeed) { _, value in
              updateCoordinatorAfterViewUpdate {
                coordinator.updatePlaybackSpeed(value)
              }
            }
            Text(String(format: "%.1f×", parameters.playbackSpeed))
              .accessibilityIdentifier("playback-speed-value")
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
        .onAppear {
          playbackSpeed = coordinator.editParameters?.playbackSpeed ?? 1
        }
        .onChange(of: coordinator.editParameters?.playbackSpeed) { _, value in
          if let value { playbackSpeed = value }
        }
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
    .help("choose a destination and start size optimization")
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
  let frameCount: Int
  let startIndex: Int
  let endIndexExclusive: Int
  let onChange: @MainActor (Int, Int) -> Void

  var body: some View {
    GeometryReader { geometry in
      let trackWidth = max(1, geometry.size.width - 24)
      let lastIndex = max(0, frameCount - 1)
      let start = min(max(startIndex, 0), lastIndex)
      let end = min(max(endIndexExclusive - 1, start), lastIndex)
      let startX = 12 + trackWidth * fraction(start, lastIndex: lastIndex)
      let endX = 12 + trackWidth * fraction(end, lastIndex: lastIndex)

      ZStack(alignment: .leading) {
        Capsule()
          .fill(.quaternary)
          .frame(width: trackWidth, height: 4)
          .offset(x: 12)
        Capsule()
          .fill(Color.accentColor)
          .frame(width: max(4, endX - startX), height: 4)
          .offset(x: startX)

        GIFTimelineHandle(
          identifier: "trim-start-handle",
          label: "trim start",
          index: start,
          frameCount: frameCount,
          lastIndex: max(0, min(lastIndex, end - 1)),
          minimumIndex: 0,
          x: startX,
          trackWidth: trackWidth,
          currentRange: start..<(end + 1),
          onMove: { value in onChange(value, endIndexExclusive) }
        )

        GIFTimelineHandle(
          identifier: "trim-end-handle",
          label: "trim end",
          index: end,
          frameCount: frameCount,
          lastIndex: lastIndex,
          minimumIndex: min(lastIndex, max(0, start + 1)),
          x: endX,
          trackWidth: trackWidth,
          currentRange: start..<(end + 1),
          onMove: { value in onChange(startIndex, value + 1) }
        )
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .coordinateSpace(name: "gif-timeline")
    }
    .frame(height: 32)
    .accessibilityElement(children: .contain)
  }

  private func fraction(_ index: Int, lastIndex: Int) -> CGFloat {
    guard lastIndex > 0 else { return 0 }
    return CGFloat(index) / CGFloat(lastIndex)
  }
}

@MainActor
private struct GIFTimelineHandle: View {
  let identifier: String
  let label: String
  let index: Int
  let frameCount: Int
  let lastIndex: Int
  let minimumIndex: Int
  let x: CGFloat
  let trackWidth: CGFloat
  let currentRange: Range<Int>
  let onMove: @MainActor (Int) -> Void

  var body: some View {
    Circle()
      .fill(Color.accentColor)
      .frame(width: 18, height: 18)
      .position(x: x, y: 16)
      .gesture(
        DragGesture(minimumDistance: 0, coordinateSpace: .named("gif-timeline"))
          .onChanged { value in move(to: value.location.x) }
      )
      .accessibilityElement()
      .accessibilityLabel(label)
      .accessibilityValue("frame \(index + 1) of \(frameCount)")
      .accessibilityIdentifier(identifier)
      .accessibilityAddTraits(.isButton)
      .accessibilityAdjustableAction(adjust)
      .help("selected frames \(currentRange.lowerBound + 1) to \(currentRange.upperBound)")
  }

  private func move(to locationX: CGFloat) {
    let normalized = min(max((locationX - 12) / trackWidth, 0), 1)
    let moved = Int((normalized * CGFloat(max(0, frameCount - 1))).rounded())
    onMove(min(max(moved, minimumIndex), lastIndex))
  }

  private func adjust(_ direction: AccessibilityAdjustmentDirection) {
    let changed: Int
    switch direction {
    case .increment: changed = min(index + 1, lastIndex)
    case .decrement: changed = max(index - 1, minimumIndex)
    @unknown default: changed = index
    }
    onMove(changed)
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
