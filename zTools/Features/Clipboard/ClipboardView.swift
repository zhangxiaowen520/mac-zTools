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

    private var pinnedItems: [ClipboardItem] { filtered.filter(\.pinned) }
    private var historyItems: [ClipboardItem] { filtered.filter { !$0.pinned } }

    var body: some View {
        VStack(spacing: 0) {
            ZSearchField(placeholder: "搜索剪贴板", text: $query, onSubmit: pasteSelected)
                .padding(.horizontal, ZTheme.pad)
                .padding(.bottom, 8)

            Text("↑↓ 选择 · ↩ 粘贴 · ⌘1-9 快贴 · ⌘T 翻译")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

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
                    if !pinnedItems.isEmpty {
                        Section {
                            ForEach(pinnedItems) { item in
                                clipboardRow(item, index: filtered.firstIndex(where: { $0.id == item.id }) ?? 0)
                            }
                        } header: {
                            ZSectionLabel(title: "置顶")
                        }
                    }
                    Section {
                        ForEach(historyItems) { item in
                            clipboardRow(item, index: filtered.firstIndex(where: { $0.id == item.id }) ?? 0)
                        }
                    } header: {
                        if !pinnedItems.isEmpty {
                            ZSectionLabel(title: "历史")
                        }
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
            .padding(.horizontal, ZTheme.pad)
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

    private func clipboardRow(_ item: ClipboardItem, index: Int) -> some View {
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
        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
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
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: ZTheme.radiusChip, style: .continuous))
                    } else {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                            .frame(width: 40, height: 40)
                            .background(ZTheme.fill, in: RoundedRectangle(cornerRadius: ZTheme.radiusChip, style: .continuous))
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
                        .font(.system(size: 13))
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        if index < 9 {
                            ZKeyCap(text: "⌘\(index + 1)")
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
                        .foregroundStyle(ZTheme.accent)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: ZTheme.radiusControl, style: .continuous)
                    .fill(isSelected ? ZTheme.selectionFill : ZTheme.fillQuiet)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ZTheme.radiusControl, style: .continuous)
                    .strokeBorder(isSelected ? ZTheme.selectionStroke : Color.clear, lineWidth: 1)
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
