import AppKit
import SwiftUI

struct NoteView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store: NoteStore
    @ObservedObject private var settings: SettingsStore
    @State private var query = ""
    @State private var selectedID: String?
    @State private var editorText = ""
    @State private var showPreview = false
    @FocusState private var editorFocused: Bool

    init() {
        _store = ObservedObject(wrappedValue: AppState.shared.noteStore)
        _settings = ObservedObject(wrappedValue: AppState.shared.settings)
    }

    private var filtered: [Note] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return store.notes }
        return store.notes.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.text.localizedCaseInsensitiveContains(q)
                || $0.filename.localizedCaseInsensitiveContains(q)
        }
    }

    private var selected: Note? {
        guard let selectedID else { return nil }
        return store.notes.first { $0.filename == selectedID }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                noteList
                    .frame(minWidth: 160, idealWidth: 200, maxWidth: 260)
                editorPane
                    .frame(minWidth: 240)
            }
            Divider()
            footer
        }
        .onAppear {
            store.reload()
            if selectedID == nil { selectedID = store.notes.first?.filename }
            syncEditorFromSelection()
        }
        .onChange(of: selectedID) { _, _ in
            syncEditorFromSelection()
        }
        .onDisappear {
            commitEditor()
            store.flush()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索 Markdown…", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            Button {
                showPreview.toggle()
            } label: {
                Image(systemName: showPreview ? "pencil" : "eye")
            }
            .buttonStyle(.borderless)
            .help(showPreview ? "编辑" : "预览 Markdown")
            .disabled(selected == nil)

            Button("新建") { createNote() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var noteList: some View {
        Group {
            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                    Text(store.notes.isEmpty ? "还没有 Markdown 笔记" : "无匹配结果")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedID) {
                    ForEach(filtered) { note in
                        NoteRow(note: note)
                            .tag(note.filename)
                            .contextMenu {
                                Button("复制") { copy(note) }
                                Button(note.pinned ? "取消置顶" : "置顶") { store.togglePin(note) }
                                Button("在 Finder 显示") {
                                    NSWorkspace.shared.activateFileViewerSelecting([note.fileURL])
                                }
                                Divider()
                                Button("删除", role: .destructive) { delete(note) }
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var editorPane: some View {
        Group {
            if selected == nil {
                Text("选择或新建一篇笔记")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if showPreview {
                ScrollView {
                    markdownPreview(editorText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
            } else {
                TextEditor(text: $editorText)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .focused($editorFocused)
                    .onChange(of: editorText) { _, newValue in
                        guard let note = selected else { return }
                        store.update(note, text: newValue)
                    }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(store.notes.count) 篇 · \(settings.notesDirectory)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(settings.notesDirectory)
            Spacer()
            Button("打开目录") {
                NSWorkspace.shared.open(settings.notesDirectoryURL)
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func markdownPreview(_ source: String) -> some View {
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("空笔记")
                .foregroundStyle(.tertiary)
        } else if let attributed = try? AttributedString(
            markdown: source,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        ) {
            Text(attributed)
                .textSelection(.enabled)
        } else {
            Text(source)
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func syncEditorFromSelection() {
        editorText = selected?.text ?? ""
        editorFocused = selected != nil && !showPreview
    }

    private func createNote() {
        commitEditor()
        guard let note = store.add("# 新笔记\n\n") else { return }
        selectedID = note.filename
        showPreview = false
        editorText = note.text
        editorFocused = true
    }

    private func commitEditor() {
        guard let note = selected else { return }
        store.update(note, text: editorText)
        store.flush()
    }

    private func copy(_ note: Note) {
        PasteboardUtil.copyString(note.text)
        appState.showToast("已复制")
    }

    private func delete(_ note: Note) {
        if selectedID == note.filename {
            selectedID = store.notes.first { $0.filename != note.filename }?.filename
        }
        store.remove(note)
    }
}

private struct NoteRow: View {
    let note: Note

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Text(note.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(note.preview)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(note.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if note.pinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 3)
    }
}
