import AppKit
import SwiftUI

@main
struct GifferentApp: App {
  @NSApplicationDelegateAdaptor(GifferentAppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra("gifferent") {
      GifferentMenuContent(runtime: .shared)
    }
  }
}

@MainActor
private final class GifferentAppDelegate: NSObject, NSApplicationDelegate {
  #if DEBUG
    private var testingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
      if !ProcessInfo.processInfo.arguments.contains("--ui-testing") {
        GifferentRuntime.shared.start()
        return
      }

      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
      )
      window.title = "gifferent test menu"
      window.contentView = NSHostingView(rootView: GifferentMenuContent(runtime: .shared).padding())
      window.center()
      window.makeKeyAndOrderFront(nil)
      testingWindow = window
    }
  #endif

  #if !DEBUG
    func applicationDidFinishLaunching(_ notification: Notification) {
      GifferentRuntime.shared.start()
    }
  #endif
}

@MainActor
private struct GifferentMenuContent: View {
  @ObservedObject var runtime: GifferentRuntime
  @State private var displayedStatus: String

  init(runtime: GifferentRuntime) {
    self.runtime = runtime
    _displayedStatus = State(initialValue: runtime.status)
  }

  var body: some View {
    Text(displayedStatus)
      .accessibilityIdentifier("app-status")
      .accessibilityLabel("status")
      .accessibilityValue(displayedStatus)
      .onReceive(runtime.$status) { status in
        displayedStatus = status
      }

    if let selectionDescription = runtime.selectionDescription {
      Text(selectionDescription)
        .accessibilityIdentifier("selection-status")
        .accessibilityLabel(selectionDescription)
    }

    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
        Text(runtime.recordingFrameFixtureState)
          .accessibilityIdentifier("recording-frame-fixture-state")
          .accessibilityLabel("recording frame fixture state")
          .accessibilityValue(runtime.recordingFrameFixtureState)
      }
    #endif

    Divider()

    Button("select capture…") {
      runtime.beginSelection()
    }
    .accessibilityIdentifier("select-capture-button")

    Button(runtime.recordingActionTitle) {
      runtime.performRecordingAction()
    }
    .disabled(runtime.recordingActionIsDisabled)
    .accessibilityIdentifier("recording-action-button")

    Button("shortcuts…") {
      runtime.showHotkeySettings()
    }
    .accessibilityIdentifier("shortcuts-button")

    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
        Button("show recording frame fixture") { runtime.showRecordingFrameFixture() }
          .accessibilityIdentifier("show-recording-frame-button")
        Button("move recording frame fixture") { runtime.moveRecordingFrameFixture() }
          .accessibilityIdentifier("move-recording-frame-button")
        Button("hide recording frame fixture") { runtime.hideRecordingFrameFixture() }
          .accessibilityIdentifier("hide-recording-frame-button")
      }
    #endif

    Divider()

    Button("quit") {
      NSApplication.shared.terminate(nil)
    }
    .accessibilityIdentifier("quit-button")
  }
}

@MainActor
final class GIFPreviewWindowController: NSObject, NSWindowDelegate {
  weak var runtime: GifferentRuntime?
  let window: NSWindow
  private var mayClose = false

  init(runtime: GifferentRuntime, coordinator: RecordingCoordinator) {
    self.runtime = runtime
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    super.init()
    window.title = "gif preview"
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.contentView = NSHostingView(
      rootView: GIFPreviewView(runtime: runtime, coordinator: coordinator)
    )
  }

  func showWindow() {
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  func closeAfterCleanup() {
    mayClose = true
    window.close()
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if mayClose { return true }
    runtime?.requestPreviewClose()
    return false
  }

  func windowWillClose(_ notification: Notification) {
    runtime?.previewWindowDidClose(self)
  }
}

@MainActor
private struct GIFPreviewView: View {
  @ObservedObject var runtime: GifferentRuntime
  @ObservedObject var coordinator: RecordingCoordinator

  var body: some View {
    Group {
      switch coordinator.state {
      case .preparingPreview:
        VStack(spacing: 14) {
          ProgressView()
            .accessibilityLabel("preparing gif preview")
          Text("preparing preview")
            .accessibilityIdentifier("preview-status")
            .accessibilityValue("preparing preview")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .captured:
        VStack(spacing: 14) {
          Text("could not create a valid gif")
            .accessibilityIdentifier("preview-status")
            .accessibilityValue("could not create a valid gif")
          Text("your captured frames are still available")
          HStack {
            Button("try again") { runtime.retryPreview() }
              .accessibilityIdentifier("retry-preview-button")
            Button("discard") { runtime.requestDiscardPreview() }
              .disabled(
                coordinator.previewAction == .copying || coordinator.previewAction == .saving
              )
              .accessibilityIdentifier("discard-preview-button")
            Button("close") { runtime.requestPreviewClose() }
              .accessibilityIdentifier("close-preview-button")
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .previewReady(_, let snapshot, let gif):
        VStack(spacing: 14) {
          Text("preview ready")
            .accessibilityIdentifier("preview-status")
            .accessibilityValue("preview ready")
          AnimatedGIFView(url: gif.url)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(CGFloat(gif.width) / CGFloat(gif.height), contentMode: .fit)

          HStack(spacing: 16) {
            metadata(
              "file size",
              value: ByteCountFormatter.string(
                fromByteCount: gif.fileBytes, countStyle: .file), id: "preview-size")
            metadata("duration", value: duration(gif.durationCentiseconds), id: "preview-duration")
            metadata("dimensions", value: "\(gif.width) by \(gif.height)", id: "preview-dimensions")
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
              .disabled(
                coordinator.previewAction == .copying || coordinator.previewAction == .saving
              )
              .accessibilityIdentifier("copy-preview-button")
            Button("save…") { runtime.savePreview() }
              .keyboardShortcut("s", modifiers: .command)
              .disabled(
                coordinator.previewAction == .copying || coordinator.previewAction == .saving
              )
              .accessibilityIdentifier("save-preview-button")
            Button("discard") { runtime.requestDiscardPreview() }
              .disabled(
                coordinator.previewAction == .copying || coordinator.previewAction == .saving
              )
              .accessibilityIdentifier("discard-preview-button")
            Button("close") { runtime.requestPreviewClose() }
              .accessibilityIdentifier("close-preview-button")
          }
        }
        .padding(18)
      case .failed(let failure):
        VStack(spacing: 12) {
          Text(failureMessage(failure))
            .accessibilityIdentifier("preview-status")
            .accessibilityValue(failureMessage(failure))
          Button("close") { runtime.requestPreviewClose() }
            .accessibilityIdentifier("close-preview-button")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      default:
        Text("preparing preview")
          .accessibilityIdentifier("preview-status")
          .accessibilityValue("preparing preview")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .frame(minWidth: 440, minHeight: 360)
    .confirmationDialog(
      "discard this preview?",
      isPresented: $runtime.isPreviewCloseConfirmationPresented,
      titleVisibility: .visible
    ) {
      Button("discard", role: .destructive) { runtime.confirmPreviewDiscard() }
        .accessibilityIdentifier("confirm-preview-discard-button")
      Button("keep preview", role: .cancel) { runtime.cancelPreviewDiscard() }
        .accessibilityIdentifier("keep-preview-button")
    } message: {
      Text("the temporary gif will be deleted.")
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

  private var actionMessage: String {
    switch coordinator.previewAction {
    case .idle: ""
    case .copying: "copying"
    case .saving: "saving"
    case .copied: "copied"
    case .saved: "saved"
    case .cancelled: "save cancelled"
    case .failed: "could not export gif; try again"
    }
  }

  private func duration(_ centiseconds: Int) -> String {
    let seconds = Double(centiseconds) / 100
    return String(format: "%.2f seconds", seconds)
  }

  private func failureMessage(_ failure: RecordingCoordinatorFailure) -> String {
    switch failure {
    case .gifEncodingFailed: "could not create a valid gif; captured frames were retained"
    case .workspaceFailed, .frameStorageFailed:
      "could not store recording data; check available storage"
    default: "recording could not be completed"
    }
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
