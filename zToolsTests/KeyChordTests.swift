import XCTest
@testable import zTools

final class KeyChordTests: XCTestCase {
    func testStorageRoundTrip() {
        let chord = KeyChord(keyCode: 0, modifiers: [.option, .command])
        let decoded = KeyChord(storageValue: chord.storageValue)
        XCTAssertEqual(decoded, chord)
    }

    func testStorageRejectsInvalid() {
        XCTAssertNil(KeyChord(storageValue: "garbage"))
        XCTAssertNil(KeyChord(storageValue: "1"))
        XCTAssertNil(KeyChord(storageValue: "1|2|3"))
    }

    func testModifierMaskFiltersNonModifiers() {
        let chord = KeyChord(keyCode: 0, modifiers: [.option, .command, .capsLock, .numericPad])
        XCTAssertTrue(chord.modifiers.contains(.option))
        XCTAssertTrue(chord.modifiers.contains(.command))
        XCTAssertFalse(chord.modifiers.contains(.capsLock))
    }

    func testDisplayString() {
        XCTAssertEqual(KeyChord(keyCode: 0, modifiers: [.option]).displayString, "⌥A")
        XCTAssertEqual(KeyChord(keyCode: 31, modifiers: [.option]).displayString, "⌥O")
    }
}
