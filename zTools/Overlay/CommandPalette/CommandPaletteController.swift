import AppKit
import SwiftUI

@MainActor
final class CommandPaletteController {
    static let shared = CommandPaletteController()

    private var panel: KeyablePanel?
    private var escMonitor: Any?

    private init() {}

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() {
        if panel?.isVisible == true {
            close(restorePreviousApp: true)
        } else {
            present()
        }
    }

    func present() {
        close()
        AppState.shared.capturePreviousApp()

        let size = CGSize(width: 520, height: 420)
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        let root = CommandPaletteView(
            onClose: { [weak self] in self?.close(restorePreviousApp: true) },
            onAction: { [weak self] action in
                self?.close()
                AppState.shared.handle(action)
            },
            onPasteClipboard: { item in
                // pasteClipboardItem closes panels and restores focus
                AppState.shared.pasteClipboardItem(item)
            },
            onTranslateText: { [weak self] text in
                self?.close()
                AppState.shared.openTranslate(text: text)
            }
        )
        .environmentObject(AppState.shared)
        .frame(width: size.width, height: size.height)

        let hosting = NSHostingView(rootView: root)
        panel.contentView = hosting
        panel.setContentSize(size)

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(CGPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2 + 80
            ))
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel

        DispatchQueue.main.async { [weak panel] in
            panel?.makeKey()
            if let field = hosting.findFirstEditableTextField() {
                panel?.makeFirstResponder(field)
            }
        }

        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.close(restorePreviousApp: true)
                return nil
            }
            return event
        }
    }

    func close(restorePreviousApp: Bool = false) {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil

        if restorePreviousApp {
            AppState.shared.activatePreviousApp()
        }
    }
}

private extension NSView {
    func findFirstEditableTextField() -> NSTextField? {
        if let field = self as? NSTextField, field.isEditable { return field }
        for sub in subviews {
            if let found = sub.findFirstEditableTextField() { return found }
        }
        return nil
    }
}

private struct CommandPaletteView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store = AppState.shared.clipboardStore
    let onClose: () -> Void
    let onAction: (ToolAction) -> Void
    let onPasteClipboard: (ClipboardItem) -> Void
    let onTranslateText: (String) -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var focused: Bool

    private struct Row: Identifiable {
        enum Kind {
            case action(ToolAction)
            case clipboard(ClipboardItem)
            case settings
        }
        let id: String
        let kind: Kind
        let title: String
        let subtitle: String
        let systemImage: String
    }

    private var rows: [Row] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result: [Row] = []

        let actions: [ToolAction] = [.screenshot, .ocr, .clipboard, .note, .translate, .timestamp, .colorPicker]
        for action in actions {
            if q.isEmpty || action.title.lowercased().contains(q) || action.rawValue.contains(q) {
                result.append(Row(
                    id: "a-\(action.rawValue)",
                    kind: .action(action),
                    title: action.title,
                    subtitle: "功能",
                    systemImage: action.systemImage
                ))
            }
        }

        if q.isEmpty || "设置".contains(q) || "settings".contains(q) {
            result.append(Row(
                id: "settings",
                kind: .settings,
                title: "设置",
                subtitle: "功能",
                systemImage: "gearshape"
            ))
        }

        let clips = store.items.prefix(30).filter { item in
            guard !q.isEmpty else { return true }
            return item.preview.lowercased().contains(q)
                || (item.sourceAppName ?? "").lowercased().contains(q)
        }
        for item in clips {
            result.append(Row(
                id: "c-\(item.id.uuidString)",
                kind: .clipboard(item),
                title: item.preview,
                subtitle: item.sourceAppName.map { "剪贴板 · \($0)" } ?? "剪贴板",
                systemImage: item.kind == .image ? "photo" : "doc.on.clipboard"
            ))
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索工具、剪贴板…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .medium))
                    .focused($focused)
                    .onSubmit { activateSelected() }
                ZCloseButton(action: onClose)
            }
            .padding(16)

            Divider().opacity(0.5)

            if rows.isEmpty {
                Text("无匹配结果")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                Button {
                                    selectedIndex = index
                                    activate(row)
                                } label: {
                                    HStack(spacing: 12) {
                                        ZIconTile(systemImage: row.systemImage, size: 32)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(row.title)
                                                .font(.system(size: 13.5))
                                                .lineLimit(1)
                                                .foregroundStyle(.primary)
                                            Text(row.subtitle)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .zSelected(index == selectedIndex, radius: ZTheme.radiusControl)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(row.id)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: selectedIndex) { _, idx in
                        guard rows.indices.contains(idx) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(rows[idx].id, anchor: .center)
                        }
                    }
                }
            }

            Divider().opacity(0.5)
            HStack {
                Text("↑↓ 选择 · ↩ 执行 · Esc 关闭")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(12)
        }
        .zGlass()
        .onAppear {
            focused = true
            selectedIndex = 0
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(max(rows.count - 1, 0), selectedIndex + 1)
            return .handled
        }
    }

    private func activateSelected() {
        guard rows.indices.contains(selectedIndex) else { return }
        activate(rows[selectedIndex])
    }

    private func activate(_ row: Row) {
        switch row.kind {
        case .action(let action):
            onAction(action)
        case .settings:
            onAction(.settings)
        case .clipboard(let item):
            if item.kind == .text, query.lowercased().hasPrefix("译") || query.lowercased().hasPrefix("tr") {
                if let text = item.text { onTranslateText(text) }
            } else {
                onPasteClipboard(item)
            }
        }
    }
}
