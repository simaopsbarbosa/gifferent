import XCTest

@testable import gifferent

@MainActor
final class GlobalHotkeyTests: XCTestCase {
  func testDefaultRegistrationAwaitsDeliveryThenRoutesActions() {
    let backend = FakeHotkeyBackend()
    let controller = GlobalHotkeyController(backend: backend)
    var delivered: [GlobalHotkeyAction] = []
    controller.onAction = { delivered.append($0) }

    assertSuccess(controller.registerDefaults())
    XCTAssertEqual(backend.chords.count, 2)
    XCTAssertEqual(controller.chord(for: .capture), .capture)
    XCTAssertEqual(controller.chord(for: .record), .record)
    XCTAssertEqual(controller.deliveryState(for: .capture), .awaitingFirstPress)
    XCTAssertEqual(controller.deliveryState(for: .record), .awaitingFirstPress)

    backend.press(identifier: 2)
    backend.press(identifier: 1)
    XCTAssertEqual(delivered, [.record, .capture])
    XCTAssertEqual(controller.deliveryState(for: .capture), .observed)
    XCTAssertEqual(controller.deliveryState(for: .record), .observed)
  }

  func testOperatingSystemRegistrationErrorLeavesShortcutInactive() {
    let backend = FakeHotkeyBackend()
    backend.registrationStatus = -9878
    let controller = GlobalHotkeyController(backend: backend)

    assertFailure(controller.bind(.capture, to: .capture), equals: .systemStatus(-9878))
    XCTAssertNil(controller.chord(for: .capture))
    XCTAssertEqual(controller.deliveryState(for: .capture), .inactive)
    XCTAssertTrue(backend.chords.isEmpty)
  }

  func testDuplicateChordInAppIsRejectedBeforeCallingBackend() {
    let backend = FakeHotkeyBackend()
    let controller = GlobalHotkeyController(backend: backend)
    assertSuccess(controller.bind(.capture, to: .capture))

    assertFailure(controller.bind(.record, to: .capture), equals: .duplicateInApp)
    XCTAssertEqual(backend.registeredIDs, [1])
    XCTAssertNil(controller.chord(for: .record))
  }

  func testRebindRegistersNewChordThenUnregistersOldOne() {
    let backend = FakeHotkeyBackend()
    let controller = GlobalHotkeyController(backend: backend)
    var delivered: [GlobalHotkeyAction] = []
    controller.onAction = { delivered.append($0) }
    assertSuccess(controller.bind(.capture, to: .capture))
    backend.press(identifier: 1)

    let replacement = HotkeyChord(keyCode: 42, modifiers: HotkeyChord.capture.modifiers)
    assertSuccess(controller.bind(.capture, to: replacement))
    XCTAssertEqual(backend.registeredIDs, [1, 2])
    XCTAssertEqual(backend.unregisteredIDs, [1])
    XCTAssertEqual(controller.chord(for: .capture), replacement)
    XCTAssertEqual(controller.deliveryState(for: .capture), .awaitingFirstPress)
    backend.press(identifier: 1)
    backend.press(identifier: 2)
    XCTAssertEqual(delivered, [.capture, .capture])
    XCTAssertEqual(controller.deliveryState(for: .capture), .observed)
  }

  func testFailedRebindKeepsPreviousChordAndDelivery() {
    let backend = FakeHotkeyBackend()
    let controller = GlobalHotkeyController(backend: backend)
    assertSuccess(controller.bind(.capture, to: .capture))
    backend.press(identifier: 1)
    backend.registrationStatus = -9868

    let replacement = HotkeyChord(keyCode: 42, modifiers: HotkeyChord.capture.modifiers)
    assertFailure(controller.bind(.capture, to: replacement), equals: .systemStatus(-9868))
    XCTAssertEqual(controller.chord(for: .capture), .capture)
    XCTAssertEqual(controller.deliveryState(for: .capture), .observed)
    XCTAssertTrue(backend.unregisteredIDs.isEmpty)
  }

  func testUnregisterRemovesCallbackAndResetsDelivery() {
    let backend = FakeHotkeyBackend()
    let controller = GlobalHotkeyController(backend: backend)
    var delivered: [GlobalHotkeyAction] = []
    controller.onAction = { delivered.append($0) }
    assertSuccess(controller.bind(.capture, to: .capture))
    assertSuccess(controller.unregister(.capture))

    backend.press(identifier: 1)
    XCTAssertTrue(delivered.isEmpty)
    XCTAssertEqual(controller.deliveryState(for: .capture), .inactive)
    XCTAssertEqual(backend.unregisteredIDs, [1])
  }
}

@MainActor
private final class FakeHotkeyBackend: HotkeyRegistrationBackend {
  var registrationStatus: OSStatus = 0
  var unregistrationStatus: OSStatus = 0
  private(set) var chords: [UInt32: HotkeyChord] = [:]
  private(set) var registeredIDs: [UInt32] = []
  private(set) var unregisteredIDs: [UInt32] = []
  private var callbacks: [UInt32: @MainActor (UInt32) -> Void] = [:]

  func register(
    _ chord: HotkeyChord,
    identifier: UInt32,
    onPress: @escaping @MainActor (UInt32) -> Void
  ) -> OSStatus {
    guard registrationStatus == 0 else { return registrationStatus }
    chords[identifier] = chord
    callbacks[identifier] = onPress
    registeredIDs.append(identifier)
    return 0
  }

  func unregister(identifier: UInt32) -> OSStatus {
    guard unregistrationStatus == 0 else { return unregistrationStatus }
    chords[identifier] = nil
    callbacks[identifier] = nil
    unregisteredIDs.append(identifier)
    return 0
  }

  func press(identifier: UInt32) {
    callbacks[identifier]?(identifier)
  }
}

private func assertSuccess(
  _ result: Result<Void, HotkeyRegistrationFailure>, file: StaticString = #filePath,
  line: UInt = #line
) {
  if case .failure(let error) = result {
    XCTFail("expected success, got \(error)", file: file, line: line)
  }
}

private func assertFailure(
  _ result: Result<Void, HotkeyRegistrationFailure>,
  equals expected: HotkeyRegistrationFailure,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  switch result {
  case .success:
    XCTFail("expected failure", file: file, line: line)
  case .failure(let error):
    XCTAssertEqual(error, expected, file: file, line: line)
  }
}
