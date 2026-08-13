import SwiftUI

struct ClipboardView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store: ClipboardStore
    @State private var query = ""
    @State private var selectedID: ClipboardItem.ID?
    @State private var previewItem: ClipboardItem?
    @FocusState private var listFocused: Bool

    init() {
        _store = ObservedObject(wrappedValue: AppState.shared.clipboardStore)
    }

    private var filtered: [ClipboardItem] {
        let items = store.items
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter {
            ($0.text ?? "").localizedCaseInsensitiveContains(q)
                || $0.preview.localizedCaseInsensitiveContains(q)
                || ($0.sourceAppName ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索剪贴板", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { pasteSelected() }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            Text("↑↓ 选择 · ↩ 粘贴 · ⌘1-9 快贴 · ⌘T 翻译")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clipboard")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(query.isEmpty ? "暂无历史记录" : "无匹配结果")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedID) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                        ClipboardRow(
                            item: item,
                            index: index,
                            isSelected: selectedID == item.id
                        ) {
                            store.paste(item)
                            appState.panelController.close()
                        } onPin: {
                            store.togglePin(item)
                        } onCopy: {
                            copy(item)
                        } onDelete: {
                            store.remove(item)
                            if selectedID == item.id { selectedID = filtered.first?.id }
                        } onTranslate: {
                            translate(item)
                        } onPreview: {
                            previewItem = item
                        }
                        .tag(item.id)
                        .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .focused($listFocused)
                .onAppear {
                    if selectedID == nil { selectedID = filtered.first?.id }
                    listFocused = true
                }
                .onChange(of: filtered.map(\.id)) { _, ids in
                    if let selectedID, ids.contains(selectedID) { return }
                    self.selectedID = ids.first
                }
            }

            HStack {
                Toggle("暂停记录", isOn: $appState.isClipboardPaused)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Spacer()
                Button("清空") { store.clear(keepPinned: true) }
                    .font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .onKeyPress(.return) {
            pasteSelected()
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveSelection(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(1)
            return .handled
        }
        .background(hotkeyButtons)
        .sheet(item: $previewItem) { item in
            ClipboardPreviewSheet(item: item) {
                previewItem = nil
            } onPaste: {
                store.paste(item)
                previewItem = nil
                appState.panelController.close()
            } onTranslate: {
                previewItem = nil
                translate(item)
            }
        }
    }

    /// 隐藏按钮承载 ⌘1-9 / ⌘T
    private var hotkeyButtons: some View {
        ZStack {
            ForEach(1...9, id: \.self) { n in
                Button("") {
                    pasteAt(n - 1)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
                .opacity(0.001)
                .frame(width: 1, height: 1)
            }
            Button("") {
                if let id = selectedID, let item = filtered.first(where: { $0.id == id }) {
                    translate(item)
                }
            }
            .keyboardShortcut("t", modifiers: .command)
            .opacity(0.001)
            .frame(width: 1, height: 1)
        }
        .allowsHitTesting(false)
    }

    private func moveSelection(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        let ids = filtered.map(\.id)
        let current = selectedID.flatMap { ids.firstIndex(of: $0) } ?? 0
        let next = min(max(current + delta, 0), ids.count - 1)
        selectedID = ids[next]
    }

    private func pasteSelected() {
        guard let id = selectedID, let item = filtered.first(where: { $0.id == id }) else { return }
        store.paste(item)
        appState.panelController.close()
    }

    private func pasteAt(_ index: Int) {
        guard index < filtered.count else { return }
        store.paste(filtered[index])
        appState.panelController.close()
    }

    private func copy(_ item: ClipboardItem) {
        if item.kind == .text, let text = item.text {
            PasteboardUtil.copyString(text)
        } else if let image = item.nsImage {
            PasteboardUtil.copyImage(image)
        }
        appState.showToast("已复制")
    }

    private func translate(_ item: ClipboardItem) {
        guard item.kind == .text, let text = item.text, !text.isEmpty else {
            appState.showToast("仅支持翻译文本")
            return
        }
        appState.openTranslate(text: text)
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let onPaste: () -> Void
    let onPin: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onTranslate: () -> Void
    let onPreview: () -> Void

    var body: some View {
        Button(action: onPaste) {
            HStack(alignment: .center, spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    if item.kind == .image, let image = item.nsImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    } else {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    if let icon = item.sourceIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 14, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            .offset(x: 2, y: 2)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.preview)
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        if index < 9 {
                            Text("⌘\(index + 1)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        if let name = item.sourceAppName {
                            Text(name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text(item.createdAt, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("粘贴", action: onPaste)
            Button("复制", action: onCopy)
            if item.kind == .text {
                Button("翻译", action: onTranslate)
            }
            Button("预览", action: onPreview)
            Button(item.pinned ? "取消置顶" : "置顶", action: onPin)
            Divider()
            Button("删除", role: .destructive, action: onDelete)
        }
    }
}

private struct ClipboardPreviewSheet: View {
    let item: ClipboardItem
    let onClose: () -> Void
    let onPaste: () -> Void
    let onTranslate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("预览")
                    .font(.headline)
                Spacer()
                Button("关闭", action: onClose)
            }
            if item.kind == .image, let image = item.nsImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                ScrollView {
                    Text(item.text ?? "")
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack {
                if item.kind == .text {
                    Button("翻译", action: onTranslate)
                }
                Spacer()
                Button("粘贴", action: onPaste)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 480, height: 420)
    }
}
