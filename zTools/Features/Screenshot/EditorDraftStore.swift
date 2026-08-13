import AppKit
import Foundation

/// 截图编辑草稿：保存原图与标注，支持再次打开继续编辑。
enum EditorDraftStore {
    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("zTools/editorDraft", isDirectory: true)
    }

    static func save(image: NSImage, strokes: [AnnotationStroke]) {
        let dir = directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = RetinaImage.pngData(from: image) {
            try? data.write(to: dir.appendingPathComponent("image.png"), options: .atomic)
        }
        let stored = strokes.map(StoredAnnotationStroke.init)
        if let json = try? JSONEncoder().encode(stored) {
            try? json.write(to: dir.appendingPathComponent("strokes.json"), options: .atomic)
        }
    }

    static func load() -> (image: NSImage, strokes: [AnnotationStroke])? {
        let dir = directory
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("image.png")),
              let image = NSImage(data: data) else { return nil }
        var strokes: [AnnotationStroke] = []
        if let json = try? Data(contentsOf: dir.appendingPathComponent("strokes.json")),
           let stored = try? JSONDecoder().decode([StoredAnnotationStroke].self, from: json) {
            strokes = stored.compactMap { $0.toStroke() }
        }
        return (image, strokes)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}
