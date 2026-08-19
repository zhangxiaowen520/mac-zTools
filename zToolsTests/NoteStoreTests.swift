import XCTest
@testable import zTools

@MainActor
final class NoteStoreTests: XCTestCase {
    private func tempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zToolsNotes-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testAddWritesMarkdownFile() {
        let dir = tempDirectory()
        let store = NoteStore(directory: dir)
        store.add("# Hello\n\nworld")
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.notes.first?.title, "Hello")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Hello.md").path))
    }

    func testAddIgnoresBlank() {
        let store = NoteStore(directory: tempDirectory())
        store.add("   ")
        XCTAssertTrue(store.notes.isEmpty)
    }

    func testSlugFromHeading() {
        XCTAssertEqual(NoteStore.slug(from: "# 我的笔记\n正文"), "我的笔记")
        XCTAssertFalse(NoteStore.slug(from: "# a/b:c").contains("/"))
    }

    func testPinSortsToTop() {
        let store = NoteStore(directory: tempDirectory())
        store.add("# first\n")
        store.add("# second\n")
        XCTAssertEqual(store.notes.first?.title, "second")
        let first = store.notes.first(where: { $0.title == "first" })!
        store.togglePin(first)
        XCTAssertEqual(store.notes.first?.title, "first")
        XCTAssertTrue(store.notes.first?.pinned == true)
    }

    func testRemoveDeletesFile() {
        let dir = tempDirectory()
        let store = NoteStore(directory: dir)
        store.add("# gone\n")
        let note = store.notes[0]
        store.remove(note)
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: note.fileURL.path))
    }

    func testReloadPicksExistingMarkdown() {
        let dir = tempDirectory()
        let url = dir.appendingPathComponent("existing.md")
        try? "# Existing\n\nfrom disk".write(to: url, atomically: true, encoding: .utf8)
        let store = NoteStore(directory: dir)
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.notes.first?.title, "Existing")
        XCTAssertTrue(store.notes.first?.text.contains("from disk") == true)
    }

    func testSaveLoadRoundTrip() {
        let dir = tempDirectory()
        let store = NoteStore(directory: dir)
        store.add("# one\nA")
        store.add("# two\nB")
        store.flush()

        let reloaded = NoteStore(directory: dir)
        XCTAssertEqual(reloaded.notes.count, 2)
        XCTAssertTrue(reloaded.notes.contains { $0.title == "one" })
        XCTAssertTrue(reloaded.notes.contains { $0.title == "two" })
    }

    func testSetDirectorySwitchesFolder() {
        let a = tempDirectory()
        let b = tempDirectory()
        let store = NoteStore(directory: a)
        store.add("# only-a\n")
        store.setDirectory(b)
        XCTAssertTrue(store.notes.isEmpty)
        store.add("# only-b\n")
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.appendingPathComponent("only-b.md").path))
    }

    func testPinPersistsAcrossReload() {
        let dir = tempDirectory()
        let store = NoteStore(directory: dir)
        store.add("# keep\n")
        store.togglePin(store.notes[0])
        store.flush()

        let reloaded = NoteStore(directory: dir)
        XCTAssertTrue(reloaded.notes.first?.pinned == true)
    }
}
