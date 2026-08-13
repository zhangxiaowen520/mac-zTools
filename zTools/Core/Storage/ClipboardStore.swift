import AppKit
import Foundation

struct ClipboardItem: Identifiable, Equatable {
    enum Kind: String {
        case text
        case image
    }

    let id: UUID
    let kind: Kind
    let text: String?
    let imageData: Data?
    let createdAt: Date
    var pinned: Bool
    let sourceAppName: String?
    let sourceBundleID: String?

    var preview: String {
        switch kind {
        case .text:
            let value = text ?? ""
            return value.count > 120 ? String(value.prefix(120)) + "…" : value
        case .image:
            return "图片"
        }
    }

    var nsImage: NSImage? {
        guard let imageData else { return nil }
        return NSImage(data: imageData)
    }

    var sourceIcon: NSImage? {
        guard let bundleID = sourceBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private var limit: Int
    private let fileURL: URL
    private let clipsDir: URL
    private var saveWorkItem: DispatchWorkItem?

    private static let persistQueue = DispatchQueue(label: "com.zeno.ztools.clipboard.persist", qos: .utility)

    init(limit: Int, directory: URL? = nil) {
        self.limit = max(10, limit)
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("zTools", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("clipboard.json")
        clipsDir = dir.appendingPathComponent("clips", isDirectory: true)
        try? FileManager.default.createDirectory(at: clipsDir, withIntermediateDirectories: true)
        load()
    }

    func updateLimit(_ newLimit: Int) {
        limit = max(10, newLimit)
        trim()
        save()
    }

    func add(_ item: ClipboardItem) {
        if let text = item.text {
            items.removeAll { $0.kind == .text && $0.text == text && !$0.pinned }
        }
        items.insert(item, at: 0)
        trim()
        save()
    }

    func togglePin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(of: item) else { return }
        items[index].pinned.toggle()
        save()
    }

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear(keepPinned: Bool = true) {
        if keepPinned {
            items.removeAll { !$0.pinned }
        } else {
            items.removeAll()
        }
        save()
    }

    func item(at index: Int) -> ClipboardItem? {
        guard index >= 0, index < items.count else { return nil }
        return items[index]
    }

    func paste(_ item: ClipboardItem) {
        // Route through AppState so panels close and previous app is activated
        AppState.shared.pasteClipboardItem(item)
    }

    func writeToPasteboard(_ item: ClipboardItem) {
        switch item.kind {
        case .text:
            if let text = item.text {
                PasteboardUtil.copyString(text)
            }
        case .image:
            if let image = item.nsImage {
                PasteboardUtil.copyImage(image)
            }
        }
    }

    private func trim() {
        let pinned = items.filter(\.pinned)
        var unpinned = items.filter { !$0.pinned }
        let remaining = max(0, limit - pinned.count)
        if unpinned.count > remaining {
            unpinned = Array(unpinned.prefix(remaining))
        }
        items = pinned + unpinned
        items.sort { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func save() {
        schedulePersist()
    }

    /// 退出前同步落盘，避免 debounce 未触发的最后一次修改丢失。
    func flush() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        let snapshot = items
        let jsonURL = fileURL
        let clips = clipsDir
        Self.persistQueue.sync {
            ClipboardStore.persist(items: snapshot, jsonURL: jsonURL, clipsDir: clips)
        }
    }

    private func schedulePersist() {
        saveWorkItem?.cancel()
        let snapshot = items
        let jsonURL = fileURL
        let clips = clipsDir
        let work = DispatchWorkItem {
            ClipboardStore.persist(items: snapshot, jsonURL: jsonURL, clipsDir: clips)
        }
        saveWorkItem = work
        Self.persistQueue.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// 后台持久化：图片写独立文件，JSON 只存元数据与文件引用，避免主线程全量 base64 编码。
    private static func persist(items: [ClipboardItem], jsonURL: URL, clipsDir: URL) {
        let fm = FileManager.default
        var referenced = Set<String>()

        for item in items where item.kind == .image {
            guard var bytes = item.imageData else { continue }
            let name = "\(item.id.uuidString).png"
            referenced.insert(name)
            let url = clipsDir.appendingPathComponent(name)
            // 大图缩略存储，控制磁盘占用
            if bytes.count > 1_500_000, let img = NSImage(data: bytes),
               let small = thumbnailPNG(img, maxSide: 800) {
                bytes = small
            }
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               (attrs[.size] as? Int) == bytes.count {
                continue
            }
            try? bytes.write(to: url, options: .atomic)
        }

        // 清理已删除条目对应的图片文件
        if let existing = try? fm.contentsOfDirectory(atPath: clipsDir.path) {
            for name in existing where name.hasSuffix(".png") && !referenced.contains(name) {
                try? fm.removeItem(at: clipsDir.appendingPathComponent(name))
            }
        }

        let payload: [[String: Any]] = items.map { item in
            var dict: [String: Any] = [
                "id": item.id.uuidString,
                "kind": item.kind.rawValue,
                "createdAt": item.createdAt.timeIntervalSince1970,
                "pinned": item.pinned
            ]
            if let text = item.text { dict["text"] = text }
            if item.kind == .image { dict["imageFile"] = "\(item.id.uuidString).png" }
            if let name = item.sourceAppName { dict["sourceAppName"] = name }
            if let bid = item.sourceBundleID { dict["sourceBundleID"] = bid }
            return dict
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? data.write(to: jsonURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        items = raw.compactMap { dict in
            guard let idString = dict["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let kindRaw = dict["kind"] as? String,
                  let kind = ClipboardItem.Kind(rawValue: kindRaw),
                  let ts = dict["createdAt"] as? TimeInterval else { return nil }
            var imageData: Data?
            if kind == .image {
                if let name = dict["imageFile"] as? String {
                    imageData = try? Data(contentsOf: clipsDir.appendingPathComponent(name))
                }
                // 兼容旧格式：base64 内联的图片
                if imageData == nil, let b64 = dict["imageData"] as? String {
                    imageData = Data(base64Encoded: b64)
                }
            }
            return ClipboardItem(
                id: id,
                kind: kind,
                text: dict["text"] as? String,
                imageData: imageData,
                createdAt: Date(timeIntervalSince1970: ts),
                pinned: dict["pinned"] as? Bool ?? false,
                sourceAppName: dict["sourceAppName"] as? String,
                sourceBundleID: dict["sourceBundleID"] as? String
            )
        }
    }

    static func thumbnailPNG(_ image: NSImage, maxSide: CGFloat) -> Data? {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height, 1))
        let target = NSSize(width: size.width * scale, height: size.height * scale)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(target.width),
            pixelsHigh: Int(target.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: CGRect(origin: .zero, size: target))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
