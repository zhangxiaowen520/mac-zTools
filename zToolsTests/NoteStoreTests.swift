import XCTest
@testable import zTools

@MainActor
final class NoteStoreTests: XCTestCase {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("zToolsNotes-\(UUID().uuidString)", isDirectory: true)
    }

    func testAddTrimsWhitespace() {
        let store = NoteStore(directory: tempDirectory())
        store.add("   hello world  ")
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.notes.first?.text, "hello world")
    }

    func testAddIgnoresBlank() {
        let store = NoteStore(directory: tempDirectory())
        store.add("   ")
        XCTAssertTrue(store.notes.isEmpty)
    }

    func testPinSortsToTop() {
        let store = NoteStore(directory: tempDirectory())
        store.add("first")
        store.add("second")
        XCTAssertEqual(store.notes.first?.text, "second")
        let first = store.notes.first(where: { $0.text == "first" })!
        store.togglePin(first)
        XCTAssertEqual(store.notes.first?.text, "first")
        XCTAssertTrue(store.notes.first?.pinned == true)
    }

    func testRemove() {
        let store = NoteStore(directory: tempDirectory())
        store.add("a")
        store.add("b")
        let a = store.notes.first(where: { $0.text == "a" })!
        store.remove(a)
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.notes.first?.text, "b")
    }

    func testClear() {
        let store = NoteStore(directory: tempDirectory())
        store.add("a")
        store.add("b")
        store.clear()
        XCTAssertTrue(store.notes.isEmpty)
    }

    func testSaveLoadRoundTrip() {
        let dir = tempDirectory()
        let store = NoteStore(directory: dir)
        store.add("note one")
        store.add("note two")
        store.flush()

        let reloaded = NoteStore(directory: dir)
        XCTAssertEqual(reloaded.notes.count, 2)
        XCTAssertTrue(reloaded.notes.contains { $0.text == "note one" })
        XCTAssertTrue(reloaded.notes.contains { $0.text == "note two" })
    }
}
