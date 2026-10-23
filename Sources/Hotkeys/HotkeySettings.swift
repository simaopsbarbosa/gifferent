import AppKit
import Carbon
import Combine
import SwiftUI

struct SavedHotkey: Equatable {
  let chord: HotkeyChord
  let keyLabel: String

  static let capture = SavedHotkey(chord: .capture, keyLabel: "G")
  static let record = SavedHotkey(chord: .record, keyLabel: "R")

  var displayLabel: String {
    var label = ""
    if chord.modifiers & UInt32(controlKey) != 0 { label += "⌃" }
    if chord.modifiers & UInt32(optionKey) != 0 { label += "⌥" }
    if chord.modifiers & UInt32(shiftKey) != 0 { label += "⇧" }
    if chord.modifiers & UInt32(cmdKey) != 0 { label += "⌘" }
    return label + keyLabel
  }
}

@MainActor
final class HotkeySettingsStore: ObservableObject {
  @Published private(set) var captureShortcut: SavedHotkey
  @Published private(set) var recordShortcut: SavedHotkey
  @Published private(set) var editingAction: GlobalHotkeyAction?
  @Published private(set) var message: String?
  @Published private var deliveryRevision = 0

  var onAction: ((GlobalHotkeyAction) -> Void)?

  private let controller: GlobalHotkeyController
  private let defaults: UserDefaults
  private let keyPrefix: String
  private var failures: [GlobalHotkeyAction: HotkeyRegistrationFailure] = [:]

  init(
    controller: GlobalHotkeyController,
    defaults: UserDefaults = .standard,
    keyPrefix: String = "gifferent.hotkey"
  ) {
    self.controller = controller
    self.defaults = defaults
    self.keyPrefix = keyPrefix
    captureShortcut = Self.read(.capture, from: defaults, prefix: keyPrefix) ?? .capture
    recordShortcut = Self.read(.record, from: defaults, prefix: keyPrefix) ?? .record
  }

  func start() {
    controller.onAction = { [weak self] action in
      self?.deliveryRevision &+= 1
      self?.onAction?(action)
    }
    register(.capture, shortcut: captureShortcut)
    register(.record, shortcut: recordShortcut)
  }

  func beginEditing(_ action: GlobalHotkeyAction) {
    message = nil
    editingAction = action
  }

  func cancelEditing() {
    editingAction = nil
  }

  func setShortcut(_ shortcut: SavedHotkey, for action: GlobalHotkeyAction) {
    guard Self.isSupported(shortcut.chord) else {
      message = "add ⌃, ⌥, or ⌘ to the key."
      return
    }

    switch controller.bind(action, to: shortcut.chord) {
    case .success:
      save(shortcut, for: action)
      failures[action] = nil
      message = "shortcut saved. press it from another app to check it works."
      editingAction = nil
      deliveryRevision &+= 1
    case .failure(let failure):
      failures[action] = failure
      message = failureMessage(failure)
    }
  }

  func shortcut(for action: GlobalHotkeyAction) -> SavedHotkey {
    switch action {
    case .capture: captureShortcut
    case .record: recordShortcut
    }
  }

  func status(for action: GlobalHotkeyAction) -> String {
    _ = deliveryRevision
    if let failure = failures[action] {
      return failureMessage(failure)
    }
    switch controller.deliveryState(for: action) {
    case .inactive:
      return "shortcut unavailable."
    case .awaitingFirstPress:
      return "unverified shortcut. press it from another app to check it works."
    case .observed:
      return "shortcut received."
    }
  }

  func isVerified(_ action: GlobalHotkeyAction) -> Bool {
    failures[action] == nil && controller.deliveryState(for: action) == .observed
  }

  private func register(_ action: GlobalHotkeyAction, shortcut: SavedHotkey) {
    switch controller.bind(action, to: shortcut.chord) {
    case .success:
      failures[action] = nil
    case .failure(let failure):
      failures[action] = failure
      message = failureMessage(failure)
    }
    deliveryRevision &+= 1
  }

  private func save(_ shortcut: SavedHotkey, for action: GlobalHotkeyAction) {
    let key = Self.storageKey(for: action, prefix: keyPrefix)
    defaults.set(
      [
        "keyCode": Int(shortcut.chord.keyCode),
        "modifiers": Int(shortcut.chord.modifiers),
        "keyLabel": shortcut.keyLabel,
      ] as [String: Any],
      forKey: key
    )
    switch action {
    case .capture: captureShortcut = shortcut
    case .record: recordShortcut = shortcut
    }
  }

  private static func read(
    _ action: GlobalHotkeyAction, from defaults: UserDefaults, prefix: String
  ) -> SavedHotkey? {
    guard
      let stored = defaults.dictionary(forKey: storageKey(for: action, prefix: prefix)),
      let keyCode = stored["keyCode"] as? Int,
      let modifiers = stored["modifiers"] as? Int,
      let keyLabel = stored["keyLabel"] as? String,
      let code = UInt32(exactly: keyCode),
      let flags = UInt32(exactly: modifiers),
      isSupported(HotkeyChord(keyCode: code, modifiers: flags)),
      (1...8).contains(keyLabel.count)
    else { return nil }
    return SavedHotkey(chord: HotkeyChord(keyCode: code, modifiers: flags), keyLabel: keyLabel)
  }

  private static func isSupported(_ chord: HotkeyChord) -> Bool {
    let supportedModifiers = UInt32(controlKey | optionKey | cmdKey | shiftKey)
    let primaryModifiers = UInt32(controlKey | optionKey | cmdKey)
    return chord.modifiers & ~supportedModifiers == 0
      && chord.modifiers & primaryModifiers != 0
  }

  private static func storageKey(for action: GlobalHotkeyAction, prefix: String) -> String {
    switch action {
    case .capture: "\(prefix).capture"
    case .record: "\(prefix).record"
    }
  }

  private func failureMessage(_ failure: HotkeyRegistrationFailure) -> String {
    switch failure {
    case .duplicateInApp:
      "choose a different shortcut for each action."
    case .systemStatus:
      "couldn't register this shortcut. choose another combination."
    case .cleanupStatus:
      "couldn't replace the shortcut. quit and reopen gifferent, then try again."
    }
  }
}

struct HotkeySettingsView: View {
  @ObservedObject var store: HotkeySettingsStore

  var body: some View {
    Form {
      shortcutRow("select capture", action: .capture)
      shortcutRow("record / stop", action: .record)
      if let message = store.message {
        Text(message)
          .font(.callout)
          .accessibilityIdentifier("hotkey-message")
      }
    }
    .formStyle(.grouped)
    .frame(minWidth: 380)
  }

  @ViewBuilder
  private func shortcutRow(_ title: String, action: GlobalHotkeyAction) -> some View {
    LabeledContent(title) {
      VStack(alignment: .trailing, spacing: 4) {
        if store.editingAction == action {
          KeyCaptureField(
            onCapture: { shortcut in store.setShortcut(shortcut, for: action) },
            onCancel: { store.cancelEditing() }
          )
          .frame(width: 220, height: 28)
          .accessibilityLabel("press a new shortcut for \(title); escape cancels")
          Button("cancel") { store.cancelEditing() }
        } else {
          Button(store.shortcut(for: action).displayLabel) { store.beginEditing(action) }
            .accessibilityLabel("change \(title) shortcut")
            .accessibilityValue(store.shortcut(for: action).displayLabel)
            .accessibilityIdentifier("hotkey-\(action)-button")
        }
        Label(
          store.status(for: action),
          systemImage: store.isVerified(action) ? "checkmark.circle" : "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("hotkey-\(action)-status")
      }
    }
  }
}

private struct KeyCaptureField: NSViewRepresentable {
  let onCapture: (SavedHotkey) -> Void
  let onCancel: () -> Void

  func makeNSView(context: Context) -> KeyCaptureNSView {
    let view = KeyCaptureNSView()
    view.onCapture = onCapture
    view.onCancel = onCancel
    view.setAccessibilityRole(.textField)
    view.setAccessibilityLabel("press a new shortcut; escape cancels")
    return view
  }

  func updateNSView(_ view: KeyCaptureNSView, context: Context) {
    view.onCapture = onCapture
    view.onCancel = onCancel
  }
}

private final class KeyCaptureNSView: NSView {
  var onCapture: ((SavedHotkey) -> Void)?
  var onCancel: (() -> Void)?

  override var acceptsFirstResponder: Bool { true }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    window?.makeFirstResponder(self)
  }

  override func keyDown(with event: NSEvent) {
    guard !event.isARepeat else { return }
    if event.keyCode == UInt16(kVK_Escape) {
      onCancel?()
      return
    }
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    var modifiers: UInt32 = 0
    if flags.contains(.control) { modifiers |= UInt32(controlKey) }
    if flags.contains(.option) { modifiers |= UInt32(optionKey) }
    if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
    if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
    let label = event.charactersIgnoringModifiers?.uppercased() ?? ""
    guard !label.isEmpty else { return }
    onCapture?(
      SavedHotkey(
        chord: HotkeyChord(keyCode: UInt32(event.keyCode), modifiers: modifiers),
        keyLabel: String(label.prefix(8))
      )
    )
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.controlBackgroundColor.setFill()
    NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    let text = "press shortcut · esc cancels" as NSString
    text.draw(
      at: NSPoint(x: 8, y: max(4, (bounds.height - 14) / 2)),
      withAttributes: [.foregroundColor: NSColor.labelColor, .font: NSFont.systemFont(ofSize: 11)]
    )
  }
}
