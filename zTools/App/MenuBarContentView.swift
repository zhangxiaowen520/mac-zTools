import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings: SettingsStore

    init() {
        _settings = ObservedObject(wrappedValue: AppState.shared.settings)
    }

    var body: some View {
        Menu("截图") {
            hotkeyButton("选区截图", .screenshot) { appState.handle(.screenshot) }
            hotkeyButton("全屏截图", .screenshotFullscreen) { appState.handle(.screenshotFullscreen) }
            hotkeyButton("延时全屏", .screenshotDelay) { appState.handle(.screenshotDelay) }
            hotkeyButton("光标下窗口", .screenshotWindow) { appState.handle(.screenshotWindow) }
            hotkeyButton("上次区域", .screenshotLastRegion) { appState.handle(.screenshotLastRegion) }
            hotkeyButton("预设尺寸", .screenshotPreset) { appState.handle(.screenshotPreset) }
        }

        hotkeyButton("OCR 识别", .ocr) { appState.handle(.ocr) }
        hotkeyButton("剪贴板历史", .clipboard) { appState.handle(.clipboard) }
        hotkeyButton("笔记", .note) { appState.handle(.note) }
        hotkeyButton("翻译", .translate) { appState.handle(.translate) }
        hotkeyButton("时间戳", .timestamp) { appState.handle(.timestamp) }
        hotkeyButton("取色", .colorPicker) { appState.handle(.colorPicker) }
        hotkeyButton("命令面板", .commandPalette) { appState.handle(.commandPalette) }
        hotkeyButton("划词翻译", .selectionTranslate) { appState.handle(.selectionTranslate) }

        Divider()
        Button("继续上次编辑") { appState.resumeEditor() }

        Divider()
        Button("检查更新…") {
            Task {
                await UpdateChecker.shared.check(manual: true)
                appState.openSettings()
                if let msg = UpdateChecker.shared.statusMessage {
                    appState.showToast(msg)
                }
            }
        }

        Divider()

        Toggle("显示悬浮球", isOn: $appState.showFloatingBall)
        Toggle("显示灵动岛", isOn: $appState.showDynamicIsland)
        Toggle("暂停剪贴板记录", isOn: $appState.isClipboardPaused)

        Divider()

        Button("设置…") { appState.openSettings() }
            .keyboardShortcut(",", modifiers: .command)

        Button("退出 zTools") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    @ViewBuilder
    private func hotkeyButton(_ title: String, _ id: SettingsStore.HotKeyID, action: @escaping () -> Void) -> some View {
        let chord = settings.hotKey(for: id)
        if let chord, let ch = chord.keyEquivalentCharacter {
            Button(LocalizedStringKey(title), action: action)
                .keyboardShortcut(KeyEquivalent(ch), modifiers: chord.eventModifiers)
        } else if let chord {
            // Non-printable key: show in title so user still sees it
            Button(LocalizedStringKey("\(title)    \(chord.displayString)"), action: action)
        } else {
            Button(LocalizedStringKey(title), action: action)
        }
    }
}
