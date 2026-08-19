import Foundation

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    let createdAt: Date
    var updatedAt: Date
    var pinned: Bool

    var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 80 ? String(trimmed.prefix(80)) + "…" : trimmed
    }
}

@MainActor
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [Note] = []

    private let fileURL: URL
    private var saveWorkItem: DispatchWorkItem?

    private static let persistQueue = DispatchQueue(label: "com.zeno.ztools.note.persist", qos: .utility)

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("zTools", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("notes.json")
        load()
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let note = Note(id: UUID(), text: trimmed, createdAt: Date(), updatedAt: Date(), pinned: false)
        notes.insert(note, at: 0)
        sort()
        schedulePersist()
    }

    func togglePin(_ note: Note) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].pinned.toggle()
        sort()
        schedulePersist()
    }

    func remove(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        schedulePersist()
    }

    func clear() {
        notes.removeAll()
        schedulePersist()
    }

    /// 退出前同步落盘，避免 debounce 未触发的最后一次修改丢失。
    func flush() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        let snapshot = notes
        let url = fileURL
        Self.persistQueue.sync {
            Self.persist(snapshot, to: url)
        }
    }

    private func sort() {
        notes.sort {
            if $0.pinned != $1.pinned { return $0.pinned && !$1.pinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private func schedulePersist() {
        saveWorkItem?.cancel()
        let snapshot = notes
        let url = fileURL
        let work = DispatchWorkItem {
            Self.persist(snapshot, to: url)
        }
        saveWorkItem = work
        Self.persistQueue.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private static func persist(_ notes: [Note], to url: URL) {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Note].self, from: data) else { return }
        notes = decoded
        sort()
    }
}
