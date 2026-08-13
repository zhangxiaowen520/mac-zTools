import XCTest
@testable import zTools

@MainActor
final class ClipboardStoreTests: XCTestCase {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("zToolsTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeText(_ text: String, pinned: Bool = false) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .text,
            text: text,
            imageData: nil,
            createdAt: Date(),
            pinned: pinned,
            sourceAppName: "TestApp",
            sourceBundleID: "com.test.app"
        )
    }

    func testLimitEnforced() {
        let store = ClipboardStore(limit: 10, directory: tempDirectory())
        for i in 0..<15 {
            store.add(makeText("item \(i)"))
        }
        XCTAssertEqual(store.items.count, 10)
        XCTAssertEqual(store.items.first?.text, "item 14")
    }

    func testPinnedAlwaysKept() {
        let store = ClipboardStore(limit: 10, directory: tempDirectory())
        store.add(makeText("pinned", pinned: true))
        for i in 0..<15 {
            store.add(makeText("x\(i)"))
        }
        XCTAssertEqual(store.items.count, 10)
        XCTAssertTrue(store.items.contains { $0.text == "pinned" && $0.pinned })
        XCTAssertTrue(store.items.first?.pinned == true)
    }

    func testDeduplicateText() {
        let store = ClipboardStore(limit: 10, directory: tempDirectory())
        store.add(makeText("same"))
        store.add(makeText("same"))
        XCTAssertEqual(store.items.count, 1)
    }

    func testSaveLoadRoundTrip() {
        let dir = tempDirectory()
        let store = ClipboardStore(limit: 10, directory: dir)
        store.add(makeText("hello"))
        store.flush()

        let reloaded = ClipboardStore(limit: 10, directory: dir)
        XCTAssertEqual(reloaded.items.first?.text, "hello")
        XCTAssertEqual(reloaded.items.first?.sourceAppName, "TestApp")
        XCTAssertEqual(reloaded.items.first?.sourceBundleID, "com.test.app")
    }

    func testClearKeepsPinned() {
        let store = ClipboardStore(limit: 10, directory: tempDirectory())
        store.add(makeText("pinned", pinned: true))
        store.add(makeText("normal"))
        store.clear(keepPinned: true)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.text, "pinned")
    }
}
