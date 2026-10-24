import AppKit
import SwiftUI

@MainActor
struct GIFPreviewReadyView: View {
  @ObservedObject var runtime: GifferentRuntime
  @ObservedObject var coordinator: RecordingCoordinator
  let snapshot: RecordingSessionSnapshot
  let gif: EncodedGIF

  var body: some View {
    VStack(spacing: 14) {
      Text("preview ready")
        .accessibilityIdentifier("preview-status")
        .accessibilityValue("preview ready")
      AnimatedGIFView(url: gif.url)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(CGFloat(gif.width) / CGFloat(gif.height), contentMode: .fit)

      GIFEditControls(coordinator: coordinator)

      HStack(spacing: 16) {
        metadata(
          "file size",
          value: ByteCountFormatter.string(fromByteCount: gif.fileBytes, countStyle: .file),
          id: "preview-size"
        )
        metadata("duration", value: duration(gif.durationCentiseconds), id: "preview-duration")
        metadata(
          "dimensions", value: "\(gif.width) by \(gif.height)", id: "preview-dimensions")
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
      || coordinator.isPreviewUpdateInProgress
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
            endIndexExclusive: parameters.frameRange.endIndexExclusive
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

  private func selectForever() {
    coordinator.updateLoopMode(.forever)
  }

  private func selectOnce() {
    coordinator.updateLoopMode(.once)
  }
}

@MainActor
private struct GIFTimelineControl: View {
  let frameCount: Int
  let startIndex: Int
  let endIndexExclusive: Int

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

        GIFTimelineHandle(x: startX)
        GIFTimelineHandle(x: endX)
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
  let x: CGFloat

  var body: some View {
    Circle()
      .fill(Color.accentColor)
      .frame(width: 18, height: 18)
      .position(x: x, y: 16)
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
