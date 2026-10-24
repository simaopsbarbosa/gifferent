import AppKit
import SwiftUI

@MainActor
struct GIFPreviewReadyView: View {
  @ObservedObject var runtime: GifferentRuntime
  @ObservedObject var coordinator: RecordingCoordinator
  let snapshot: RecordingSessionSnapshot
  let gif: EncodedGIF

  private var displayedGIF: EncodedGIF {
    coordinator.displayedPreviewGIF ?? gif
  }

  var body: some View {
    VStack(spacing: 14) {
      Text("preview ready")
        .accessibilityIdentifier("preview-status")
        .accessibilityValue("preview ready")
      AnimatedGIFView(url: displayedGIF.url)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(CGFloat(displayedGIF.width) / CGFloat(displayedGIF.height), contentMode: .fit)

      if coordinator.compressedPreview == nil {
        GIFEditControls(coordinator: coordinator)
          .disabled(coordinator.isCompressionInProgress)
        GIFCompressionControls(coordinator: coordinator)
      } else {
        VStack(alignment: .leading, spacing: 8) {
          Text("compressed for \(coordinator.compressionSettings.destination.displayName)")
            .accessibilityIdentifier("compression-preview-status")
          Text(compressionTargetMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
          Button("back to original") {
            Task { await coordinator.backToOriginalPreview() }
          }
          .accessibilityIdentifier("back-to-original-button")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      HStack(spacing: 16) {
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

      if snapshot.isPartialResult {
        Text("partial recording")
          .accessibilityIdentifier("preview-partial-status")
      }

      Text(actionMessage)
        .accessibilityIdentifier("preview-action-status")
        .accessibilityValue(actionMessage)
        .accessibilityAddTraits(.updatesFrequently)

      HStack {
        Button("copy") { runtime.copyPreview() }
          .keyboardShortcut("c", modifiers: .command)
          .disabled(exportIsDisabled)
          .accessibilityIdentifier("copy-preview-button")
        Button("save…") { runtime.savePreview() }
          .keyboardShortcut("s", modifiers: .command)
          .disabled(exportIsDisabled)
          .accessibilityIdentifier("save-preview-button")
        Button("discard") { runtime.requestDiscardPreview() }
          .disabled(exportIsDisabled)
          .accessibilityIdentifier("discard-preview-button")
        Button("close") { runtime.requestPreviewClose() }
          .accessibilityIdentifier("close-preview-button")
      }
    }
  }

  private var exportIsDisabled: Bool {
    coordinator.previewAction == .copying || coordinator.previewAction == .saving
      || coordinator.isPreviewUpdateInProgress || coordinator.isCompressionInProgress
  }

  private var compressionTargetMessage: String {
    let destination = coordinator.compressionSettings.destination
    let output = ByteCountFormatter.string(fromByteCount: displayedGIF.fileBytes, countStyle: .file)
    return displayedGIF.fileBytes <= destination.targetBytes
      ? "\(output) · under the \(destination.targetLabel) target"
      : "\(output) · above the \(destination.targetLabel) target"
  }

  private var actionMessage: String {
    switch coordinator.previewAction {
    case .idle: ""
    case .updated: "gif updated"
    case .updateFailed: "could not update gif; previous preview kept"
    case .copying: "copying"
    case .saving: "saving"
    case .copied: "copied"
    case .saved: "saved"
    case .cancelled: "save cancelled"
    case .failed: "could not export gif; try again"
    }
  }

  private func metadata(_ label: String, value: String, id: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      Text(value).accessibilityIdentifier(id).accessibilityValue(value)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(label)
    .accessibilityValue(value)
  }

  private func duration(_ centiseconds: Int) -> String {
    let seconds = Double(centiseconds) / 100
    return String(format: "%.2f seconds", seconds)
  }
}

@MainActor
private struct GIFEditControls: View {
  @ObservedObject var coordinator: RecordingCoordinator
  @State private var playbackSpeed = 1.0

  var body: some View {
    Group {
      if let parameters = coordinator.editParameters, coordinator.editFrameCount > 0 {
        VStack(alignment: .leading, spacing: 10) {
          Text("trim")
            .font(.caption)
            .foregroundStyle(.secondary)
          GIFTimelineControl(
            frameCount: coordinator.editFrameCount,
            startIndex: parameters.frameRange.startIndex,
            endIndexExclusive: parameters.frameRange.endIndexExclusive,
            onChange: updateTrim
          )

          HStack {
            Text("speed")
            Slider(
              value: $playbackSpeed,
              in: 0.5...2,
              step: 0.1
            )
            .accessibilityLabel("playback speed")
            .accessibilityIdentifier("playback-speed-slider")
            .onChange(of: playbackSpeed) { _, value in
              coordinator.updatePlaybackSpeed(value)
            }
            Text(String(format: "%.1f×", parameters.playbackSpeed))
              .accessibilityIdentifier("playback-speed-value")
          }

          HStack(spacing: 8) {
            Text("loop")
            Button("forever", action: selectForever)
              .buttonStyle(.bordered)
              .accessibilityIdentifier("loop-forever-button")
              .accessibilityAddTraits(parameters.loopMode == .forever ? .isSelected : [])
            Button("once", action: selectOnce)
              .buttonStyle(.bordered)
              .accessibilityIdentifier("loop-once-button")
              .accessibilityAddTraits(parameters.loopMode == .once ? .isSelected : [])
          }

          if coordinator.isPreviewUpdateInProgress {
            Text("updating gif")
              .accessibilityIdentifier("preview-update-status")
              .accessibilityValue("updating gif")
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
    coordinator.updateTrim(startIndex: start, endIndexExclusive: end)
  }

  private func selectForever() {
    coordinator.updateLoopMode(.forever)
  }

  private func selectOnce() {
    coordinator.updateLoopMode(.once)
  }
}

@MainActor
private struct GIFCompressionControls: View {
  @ObservedObject var coordinator: RecordingCoordinator

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("compression")
        .font(.caption)
        .foregroundStyle(.secondary)
      GIFCompressionDestinationControl(coordinator: coordinator)
      GIFCompressionScaleControl(coordinator: coordinator)
      GIFCompressionDiffusionControl(coordinator: coordinator)
      GIFCompressionActionControl(coordinator: coordinator)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

@MainActor
private struct GIFCompressionDestinationControl: View {
  @ObservedObject var coordinator: RecordingCoordinator

  var body: some View {
    HStack(spacing: 8) {
      ForEach(GIFCompressionDestination.allCases) { destination in
        GIFCompressionDestinationButton(coordinator: coordinator, destination: destination)
      }
    }
  }
}

@MainActor
private struct GIFCompressionDestinationButton: View {
  @ObservedObject var coordinator: RecordingCoordinator
  let destination: GIFCompressionDestination

  private var buttonLabel: some View {
    HStack(spacing: 6) {
      Image(systemName: destination.systemImage)
        .accessibilityHidden(true)
      Text(destination.buttonTitle)
    }
  }

  private var accessibleLabel: String {
    "\(destination.displayName), \(destination.targetLabel) target, "
      + "\(destination.publishedMaximumLabel) published maximum"
  }

  private var helpText: String {
    let maximum = "published maximum: \(destination.publishedMaximumLabel)"
    let scope = "for \(destination.limitScopeDescription)"
    return "target: \(destination.targetLabel) · \(maximum) \(scope) · "
      + "checked \(destination.limitResearchDate)"
  }

  var body: some View {
    Button {
      coordinator.selectCompressionDestination(destination)
    } label: {
      buttonLabel
    }
    .buttonStyle(.bordered)
    .disabled(coordinator.isCompressionInProgress || coordinator.compressedPreview != nil)
    .accessibilityIdentifier("compression-destination-\(destination.accessibilityID)")
    .accessibilityLabel(accessibleLabel)
    .accessibilityAddTraits(
      coordinator.compressionSettings.destination == destination ? .isSelected : []
    )
    .help(helpText)
  }
}

@MainActor
private struct GIFCompressionScaleControl: View {
  @ObservedObject var coordinator: RecordingCoordinator

  var body: some View {
    HStack(spacing: 8) {
      Text("size")
      Picker(
        "size",
        selection: Binding(
          get: { coordinator.compressionSettings.scale },
          set: { coordinator.selectCompressionScale($0) }
        )
      ) {
        ForEach(GIFCompressionScale.allCases) { scale in
          Text(scale.label).tag(scale)
        }
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .accessibilityIdentifier("compression-scale-picker")
      .disabled(coordinator.isCompressionInProgress || coordinator.compressedPreview != nil)
    }
  }
}

@MainActor
private struct GIFCompressionDiffusionControl: View {
  @ObservedObject var coordinator: RecordingCoordinator

  var body: some View {
    HStack {
      Text("dithering")
      Slider(
        value: Binding(
          get: { Double(coordinator.compressionSettings.diffusionPercent) },
          set: { coordinator.setCompressionDiffusion(Int($0.rounded())) }
        ),
        in: 0...100,
        step: 5
      )
      .accessibilityLabel("dithering strength")
      .accessibilityIdentifier("compression-diffusion-slider")
      Text("\(coordinator.compressionSettings.diffusionPercent)%")
        .accessibilityIdentifier("compression-diffusion-value")
    }
    .disabled(coordinator.isCompressionInProgress || coordinator.compressedPreview != nil)
  }
}

@MainActor
private struct GIFCompressionActionControl: View {
  @ObservedObject var coordinator: RecordingCoordinator

  var body: some View {
    Group {
      if coordinator.isCompressionAvailable {
        if coordinator.isCompressionInProgress {
          HStack {
            ProgressView()
              .controlSize(.small)
              .accessibilityLabel("compressing gif")
            Text("compressing gif")
              .accessibilityIdentifier("compression-action-status")
            Button("cancel") { Task { await coordinator.cancelCompression() } }
              .accessibilityIdentifier("cancel-compression-button")
          }
        } else {
          Button("compress") { coordinator.startCompression() }
            .accessibilityIdentifier("compress-preview-button")
            .disabled(coordinator.isPreviewUpdateInProgress || coordinator.compressedPreview != nil)
        }
      } else {
        Text("compression unavailable until a verified local backend is provided")
          .font(.caption)
          .accessibilityIdentifier("compression-unavailable-status")
      }

      switch coordinator.compressionAction {
      case .failed:
        Text("could not compress gif; original preview kept")
          .accessibilityIdentifier("compression-action-status")
      case .cancelled:
        Text("compression cancelled; original preview kept")
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

  func makeNSView(context: Context) -> NSImageView {
    let view = NSImageView()
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

  func updateNSView(_ view: NSImageView, context: Context) {
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
