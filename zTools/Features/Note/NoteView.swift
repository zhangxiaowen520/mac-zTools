import SwiftUI

struct NoteView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store: NoteStore
    @State private var draft = ""
    @State private var query = ""
    @FocusState private var inputFocused: Bool

    init() {
        _store = ObservedObject(wrappedValue: AppState.shared.noteStore)
    }

    private var filtered: [Note] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return store.notes }
        return store.notes.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("记点什么…", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .onSubmit { add() }
                Button("添加") { add() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(10)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            if !store.notes.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索笔记", text: $query)
                        .textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    Text(store.notes.isEmpty ? "还没有笔记" : "无匹配结果")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filtered) { note in
                        NoteRow(
                            note: note,
                            onCopy: {
                                PasteboardUtil.copyString(note.text)
                                appState.showToast("已复制")
                            },
                            onPin: { store.togglePin(note) },
                            onDelete: { store.remove(note) }
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            HStack {
                Text("共 \(store.notes.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !store.notes.isEmpty {
                    Button("清空") { store.clear() }
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .onAppear { inputFocused = true }
    }

    private func add() {
        store.add(draft)
        draft = ""
        inputFocused = true
    }
}

private struct NoteRow: View {
    let note: Note
    let onCopy: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onCopy) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.text)
                        .font(.system(size: 12))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(note.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("点击复制")

            if note.pinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Button(action: onPin) {
                Image(systemName: note.pinned ? "pin.slash" : "pin")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(note.pinned ? "取消置顶" : "置顶")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("删除")
        }
        .padding(.vertical, 4)
    }
}
