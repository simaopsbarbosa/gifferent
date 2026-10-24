import Carbon

struct HotkeyChord: Hashable {
  let keyCode: UInt32
  let modifiers: UInt32

  static let capture = HotkeyChord(
    keyCode: UInt32(kVK_ANSI_G),
    modifiers: UInt32(controlKey | optionKey)
  )
  static let record = HotkeyChord(
    keyCode: UInt32(kVK_ANSI_R),
    modifiers: UInt32(controlKey | optionKey)
  )
}

enum GlobalHotkeyAction: CaseIterable {
  case capture
  case record
}

enum HotkeyDeliveryState: Equatable {
  case inactive
  case awaitingFirstPress
  case observed
}

enum HotkeyRegistrationFailure: Error, Equatable {
  case duplicateInApp
  case systemStatus(OSStatus)
  case cleanupStatus(OSStatus)
}

@MainActor
protocol HotkeyRegistrationBackend: AnyObject {
  func register(
    _ chord: HotkeyChord,
    identifier: UInt32,
    onPress: @escaping @MainActor (UInt32) -> Void
  ) -> OSStatus
  func unregister(identifier: UInt32) -> OSStatus
}

@MainActor
final class GlobalHotkeyController {
  private struct Registration {
    let identifier: UInt32
    let chord: HotkeyChord
    var delivery: HotkeyDeliveryState
  }

  private let backend: HotkeyRegistrationBackend
  private var registrations: [GlobalHotkeyAction: Registration] = [:]
  private var orphanedIdentifiers: Set<UInt32> = []
  private var nextIdentifier: UInt32 = 1
  var onAction: ((GlobalHotkeyAction) -> Void)?

  init(backend: HotkeyRegistrationBackend = CarbonHotkeyBackend()) {
    self.backend = backend
  }

  func chord(for action: GlobalHotkeyAction) -> HotkeyChord? {
    registrations[action]?.chord
  }

  func deliveryState(for action: GlobalHotkeyAction) -> HotkeyDeliveryState {
    registrations[action]?.delivery ?? .inactive
  }

  @discardableResult
  func registerDefaults() -> Result<Void, HotkeyRegistrationFailure> {
    switch bind(.capture, to: .capture) {
    case .failure(let failure):
      return .failure(failure)
    case .success:
      break
    }
    switch bind(.record, to: .record) {
    case .failure(let failure):
      _ = unregister(.capture)
      return .failure(failure)
    case .success:
      return .success(())
    }
  }

  @discardableResult
  func bind(
    _ action: GlobalHotkeyAction,
    to chord: HotkeyChord
  ) -> Result<Void, HotkeyRegistrationFailure> {
    if registrations[action]?.chord == chord {
      return .success(())
    }
    if registrations.contains(where: { $0.key != action && $0.value.chord == chord }) {
      return .failure(.duplicateInApp)
    }

    let identifier = nextIdentifier
    nextIdentifier &+= 1
    let status = backend.register(chord, identifier: identifier) { [weak self] deliveredID in
      self?.handlePress(identifier: deliveredID)
    }
    guard status == noErr else {
      return .failure(.systemStatus(status))
    }

    if let previous = registrations[action] {
      let cleanupStatus = backend.unregister(identifier: previous.identifier)
      guard cleanupStatus == noErr else {
        if backend.unregister(identifier: identifier) != noErr {
          orphanedIdentifiers.insert(identifier)
        }
        return .failure(.cleanupStatus(cleanupStatus))
      }
    }

    registrations[action] = Registration(
      identifier: identifier,
      chord: chord,
      delivery: .awaitingFirstPress
    )
    return .success(())
  }

  @discardableResult
  func unregister(_ action: GlobalHotkeyAction) -> Result<Void, HotkeyRegistrationFailure> {
    guard let registration = registrations[action] else { return .success(()) }
    let status = backend.unregister(identifier: registration.identifier)
    guard status == noErr else { return .failure(.cleanupStatus(status)) }
    registrations[action] = nil
    return .success(())
  }

  @discardableResult
  func unregisterAll() -> [HotkeyRegistrationFailure] {
    var failures: [HotkeyRegistrationFailure] = []
    for action in GlobalHotkeyAction.allCases {
      if case .failure(let failure) = unregister(action) {
        failures.append(failure)
      }
    }
    for identifier in orphanedIdentifiers {
      let status = backend.unregister(identifier: identifier)
      if status == noErr {
        orphanedIdentifiers.remove(identifier)
      } else {
        failures.append(.cleanupStatus(status))
      }
    }
    return failures
  }

  private func handlePress(identifier: UInt32) {
    guard let action = registrations.first(where: { $0.value.identifier == identifier })?.key
    else { return }
    registrations[action]?.delivery = .observed
    onAction?(action)
  }
}
