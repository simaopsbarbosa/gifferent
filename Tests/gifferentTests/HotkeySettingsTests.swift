import Carbon
import XCTest

@testable import gifferent

@MainActor
final class HotkeySettingsTests: XCTestCase {
  func testSuccessfulChangePersistsAndIsRestored() {
    let defaults = temporaryDefaults()
    let backend = SettingsHotkeyBackend()
    let controller = GlobalHotkeyController(backend: backend)
    let store = HotkeySettingsStore(controller: controller, defaults: defaults)
    store.start()

    let changed = SavedHotkey(
      chord: HotkeyChord(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(controlKey | shiftKey)),
      keyLabel: "H"
    )
    store.setShortcut(changed, for: .capture)

    XCTAssertEqual(controller.chord(for: .capture), changed.chord)
    XCTAssertEqual(store.shortcut(for: .capture), changed)
    let restored = HotkeySettingsStore(
      controller: GlobalHotkeyController(backend: SettingsHotkeyBackend()), defaults: defaults)
    XCTAssertEqual(restored.shortcut(for: .capture), changed)
  }

  func testFailedRegistrationRetainsOldShortcutAndDoesNotPersist() {
    let defaults = temporaryDefaults()
    let backend = SettingsHotkeyBackend()
    let controller = GlobalHotkeyController(backend: backend)
    let store = HotkeySettingsStore(controller: controller, defaults: defaults)
    store.start()
    backend.registrationStatus = -9878

    let changed = SavedHotkey(
      chord: HotkeyChord(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(controlKey)),
      keyLabel: "H"
    )
    store.setShortcut(changed, for: .capture)

    XCTAssertEqual(controller.chord(for: .capture), .capture)
    XCTAssertEqual(store.shortcut(for: .capture), .capture)
    XCTAssertTrue(store.status(for: .capture).contains("couldn't register"))
    XCTAssertNil(defaults.object(forKey: "gifferent.hotkey.capture"))
  }

  func testDuplicateAndBareKeyAreRejectedWithoutReplacingBindings() {
    let backend = SettingsHotkeyBackend()
    let controller = GlobalHotkeyController(backend: backend)
    let store = HotkeySettingsStore(controller: controller, defaults: temporaryDefaults())
    store.start()

    store.setShortcut(.capture, for: .record)
    XCTAssertEqual(controller.chord(for: .record), .record)
    XCTAssertTrue(store.status(for: .record).contains("different shortcut"))

    let bareKey = SavedHotkey(
      chord: HotkeyChord(keyCode: UInt32(kVK_ANSI_H), modifiers: 0), keyLabel: "H")
    store.setShortcut(bareKey, for: .capture)
    XCTAssertEqual(controller.chord(for: .capture), .capture)
    XCTAssertTrue(store.message?.contains("add ⌃") == true)
  }

  func testObservedPressUpdatesStatusAndForwardsAction() {
    let backend = SettingsHotkeyBackend()
    let store = HotkeySettingsStore(
      controller: GlobalHotkeyController(backend: backend), defaults: temporaryDefaults())
    var actions: [GlobalHotkeyAction] = []
    store.onAction = { actions.append($0) }
    store.start()

    XCTAssertTrue(store.status(for: .capture).contains("unverified shortcut"))
    XCTAssertFalse(store.isVerified(.capture))
    backend.press(identifier: 1)
    XCTAssertEqual(store.status(for: .capture), "shortcut received.")
    XCTAssertTrue(store.isVerified(.capture))
    XCTAssertEqual(actions, [.capture])
  }

  private func temporaryDefaults() -> UserDefaults {
    let suiteName = "gifferent.hotkey.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }
}

@MainActor
private final class SettingsHotkeyBackend: HotkeyRegistrationBackend {
  var registrationStatus: OSStatus = noErr
  private var callbacks: [UInt32: @MainActor (UInt32) -> Void] = [:]

  func register(
    _ chord: HotkeyChord,
    identifier: UInt32,
    onPress: @escaping @MainActor (UInt32) -> Void
  ) -> OSStatus {
    guard registrationStatus == noErr else { return registrationStatus }
    callbacks[identifier] = onPress
    return noErr
  }

  func unregister(identifier: UInt32) -> OSStatus {
    callbacks[identifier] = nil
    return noErr
  }

  func press(identifier: UInt32) {
    callbacks[identifier]?(identifier)
  }
}
