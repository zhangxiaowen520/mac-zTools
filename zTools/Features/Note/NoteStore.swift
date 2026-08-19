import Foundation

struct Note: Identifiable, Equatable {
    var id: String { filename }
    let filename: String
    var fileURL: URL
    var text: String
    var createdAt: Date
    var updatedAt: Date
    var pinned: Bool

    var title: String {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(8) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("#") {
                return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespaces))
            }
            return trimmed
        }
        return (filename as NSString).deletingPathExtension
    }

    var preview: String {
        let body = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .joined(separator: " ")
        if body.isEmpty { return title }
        return body.count > 80 ? String(body.prefix(80)) + "…" : body
    }
}

@MainActor
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published private(set) var directory: URL

    private var saveWorkItem: DispatchWorkItem?
    private var pendingWrites: [String: String] = [:]

    private static let persistQueue = DispatchQueue(label: "com.zeno.ztools.note.persist", qos: .utility)
    private static let indexName = ".ztools-index.json"
    private static let legacyJSONName = "notes.json"

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        migrateLegacyJSONIfNeeded()
        reload()
    }

    func setDirectory(_ url: URL) {
        flush()
        directory = url
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        migrateLegacyJSONIfNeeded()
        reload()
    }

    func reload() {
        flushPendingWritesToDisk()
        notes = Self.scan(directory: directory)
        sort()
    }

    @discardableResult
    func add(_ text: String) -> Note? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let name = uniqueFilename(from: trimmed)
        let url = directory.appendingPathComponent(name)
        let now = Date()
        let note = Note(
            filename: name,
            fileURL: url,
            text: trimmed,
            createdAt: now,
            updatedAt: now,
            pinned: false
        )
        writeFile(url: url, text: trimmed)
        notes.insert(note, at: 0)
        sort()
        return note
    }

    func update(_ note: Note, text: String) {
        guard let index = notes.firstIndex(where: { $0.filename == note.filename }) else { return }
        notes[index].text = text
        notes[index].updatedAt = Date()
        pendingWrites[note.filename] = text
        schedulePersist()
        sort()
    }

    func togglePin(_ note: Note) {
        guard let index = notes.firstIndex(where: { $0.filename == note.filename }) else { return }
        notes[index].pinned.toggle()
        sort()
        persistIndex()
    }

    func remove(_ note: Note) {
        pendingWrites.removeValue(forKey: note.filename)
        notes.removeAll { $0.filename == note.filename }
        try? FileManager.default.removeItem(at: note.fileURL)
        persistIndex()
    }

    func flush() {
        flushPendingWritesToDisk()
    }

    private func sort() {
        notes.sort {
            if $0.pinned != $1.pinned { return $0.pinned && !$1.pinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private func uniqueFilename(from text: String) -> String {
        let base = Self.slug(from: text)
        var name = "\(base).md"
        var n = 2
        let existing = Set(notes.map(\.filename))
        let fm = FileManager.default
        while existing.contains(name) || fm.fileExists(atPath: directory.appendingPathComponent(name).path) {
            name = "\(base)-\(n).md"
            n += 1
        }
        return name
    }

    static func slug(from text: String) -> String {
        let firstLine = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        var slug = firstLine.replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
        slug = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        slug = slug.components(separatedBy: invalid).joined(separator: "-")
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-. "))
        if slug.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            slug = formatter.string(from: Date())
        }
        if slug.count > 60 { slug = String(slug.prefix(60)) }
        return slug
    }

    private func schedulePersist() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.flushPendingWritesToDisk()
            }
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func flushPendingWritesToDisk() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        let writes = pendingWrites
        pendingWrites.removeAll()
        let dir = directory
        for (name, text) in writes {
            writeFile(url: dir.appendingPathComponent(name), text: text)
        }
    }

    private func writeFile(url: URL, text: String) {
        try? text.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    private static func scan(directory: URL) -> [Note] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let pinned = loadPinned(in: directory)
        var result: [Note] = []
        for url in items where url.pathExtension.lowercased() == "md" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            result.append(Note(
                filename: url.lastPathComponent,
                fileURL: url,
                text: text,
                createdAt: values?.creationDate ?? Date(),
                updatedAt: values?.contentModificationDate ?? Date(),
                pinned: pinned.contains(url.lastPathComponent)
            ))
        }
        return result
    }

    private func persistIndex() {
        let pinned = notes.filter(\.pinned).map(\.filename)
        let payload = ["pinned": pinned]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? data.write(to: directory.appendingPathComponent(Self.indexName), options: .atomic)
    }

    private static func loadPinned(in directory: URL) -> Set<String> {
        let url = directory.appendingPathComponent(indexName)
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pinned = obj["pinned"] as? [String] else { return [] }
        return Set(pinned)
    }

    /// 将旧版 notes.json 一次性迁到当前目录的 .md 文件。
    private func migrateLegacyJSONIfNeeded() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("zTools", isDirectory: true)
        guard let support else { return }
        let jsonURL = support.appendingPathComponent(Self.legacyJSONName)
        guard FileManager.default.fileExists(atPath: jsonURL.path) else { return }

        struct LegacyNote: Decodable {
            let text: String
            let pinned: Bool?
            let createdAt: Date?
            let updatedAt: Date?
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        guard let data = try? Data(contentsOf: jsonURL),
              let legacy = try? decoder.decode([LegacyNote].self, from: data) else { return }

        var pinnedNames: [String] = []
        for item in legacy {
            let trimmed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let name = uniqueFilename(from: trimmed)
            let url = directory.appendingPathComponent(name)
            writeFile(url: url, text: trimmed)
            if item.pinned == true { pinnedNames.append(name) }
        }
        if !pinnedNames.isEmpty {
            let payload = ["pinned": pinnedNames]
            if let data = try? JSONSerialization.data(withJSONObject: payload) {
                try? data.write(to: directory.appendingPathComponent(Self.indexName), options: .atomic)
            }
        }
        let bak = support.appendingPathComponent("notes.json.bak")
        try? FileManager.default.removeItem(at: bak)
        try? FileManager.default.moveItem(at: jsonURL, to: bak)
    }
}
