import Carbon

@MainActor
final class CarbonHotkeyBackend: HotkeyRegistrationBackend {
  nonisolated fileprivate static let signature: OSType = 0x6769_6666

  private var handlerReference: EventHandlerRef?
  private var hotkeyReferences: [UInt32: EventHotKeyRef] = [:]
  private var callbacks: [UInt32: @MainActor (UInt32) -> Void] = [:]

  func register(
    _ chord: HotkeyChord,
    identifier: UInt32,
    onPress: @escaping @MainActor (UInt32) -> Void
  ) -> OSStatus {
    let handlerStatus = installHandlerIfNeeded()
    guard handlerStatus == noErr else { return handlerStatus }

    var reference: EventHotKeyRef?
    let hotkeyID = EventHotKeyID(signature: Self.signature, id: identifier)
    let status = RegisterEventHotKey(
      chord.keyCode,
      chord.modifiers,
      hotkeyID,
      GetApplicationEventTarget(),
      OptionBits(kEventHotKeyNoOptions),
      &reference
    )
    guard status == noErr, let reference else {
      return status == noErr ? OSStatus(paramErr) : status
    }
    hotkeyReferences[identifier] = reference
    callbacks[identifier] = onPress
    return noErr
  }

  func unregister(identifier: UInt32) -> OSStatus {
    guard let reference = hotkeyReferences[identifier] else { return noErr }
    let status = UnregisterEventHotKey(reference)
    if status == noErr {
      hotkeyReferences[identifier] = nil
      callbacks[identifier] = nil
    }
    return status
  }

  private func installHandlerIfNeeded() -> OSStatus {
    guard handlerReference == nil else { return noErr }
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    return InstallEventHandler(
      GetApplicationEventTarget(),
      carbonHotkeyEventHandler,
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &handlerReference
    )
  }

  fileprivate func handlePress(identifier: UInt32) -> OSStatus {
    guard let callback = callbacks[identifier] else { return OSStatus(eventNotHandledErr) }
    callback(identifier)
    return noErr
  }

  isolated deinit {
    for reference in hotkeyReferences.values {
      UnregisterEventHotKey(reference)
    }
    if let handlerReference {
      RemoveEventHandler(handlerReference)
    }
  }
}

private func carbonHotkeyEventHandler(
  _: EventHandlerCallRef?,
  event: EventRef?,
  userData: UnsafeMutableRawPointer?
) -> OSStatus {
  guard let event, let userData else { return OSStatus(eventNotHandledErr) }
  var hotkeyID = EventHotKeyID()
  let status = GetEventParameter(
    event,
    EventParamName(kEventParamDirectObject),
    EventParamType(typeEventHotKeyID),
    nil,
    MemoryLayout<EventHotKeyID>.size,
    nil,
    &hotkeyID
  )
  guard status == noErr, hotkeyID.signature == CarbonHotkeyBackend.signature else {
    return OSStatus(eventNotHandledErr)
  }
  let identifier = hotkeyID.id
  let backend = Unmanaged<CarbonHotkeyBackend>.fromOpaque(userData).takeUnretainedValue()
  return MainActor.assumeIsolated {
    backend.handlePress(identifier: identifier)
  }
}
