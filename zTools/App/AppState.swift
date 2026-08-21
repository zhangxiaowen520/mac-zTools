import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var showFloatingBall: Bool
    @Published var showDynamicIsland: Bool
    @Published var isClipboardPaused: Bool = false
    @Published var toastMessage: String?
    @Published var pendingTranslateText: String = ""

    /// Frontmost app before zTools stole focus (for paste-back).
    private(set) var previousApp: NSRunningApplication?

    let settings: SettingsStore
    let clipboardStore: ClipboardStore
    let floatingBall = FloatingBallController()
    let dynamicIsland = DynamicIslandController()
    let panelController = ToolPanelController()
    let hotKeyManager = HotKeyManager()
    let pasteboardMonitor = PasteboardMonitor()
    let screenshotService = ScreenshotService()
    let ocrService = OCRService()
    let colorPickerService = ColorPickerService()
    let translateService = TranslateService()
    let noteStore: NoteStore

    private var cancellables = Set<AnyCancellable>()
    private var ownBundleID: String? { Bundle.main.bundleIdentifier }

    private init() {
        let settings = SettingsStore()
        self.settings = settings
        self.clipboardStore = ClipboardStore(limit: settings.clipboardLimit)
        self.noteStore = NoteStore(directory: settings.notesDirectoryURL)
        self.showFloatingBall = settings.showFloatingBall
        self.showDynamicIsland = settings.showDynamicIsland
    }

    /// Remember the frontmost app if it isn't zTools itself.
    func capturePreviousApp() {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        if let bid = front.bundleIdentifier, bid == ownBundleID { return }
        if front == NSRunningApplication.current { return }
        previousApp = front
    }

    /// Activate the app that was frontmost before a panel opened.
    @discardableResult
    func activatePreviousApp() -> Bool {
        guard let app = previousApp, !app.isTerminated else { return false }
        return app.activate()
    }

    /// Copy clipboard item, close overlays, restore previous app, then ⌘V.
    func pasteClipboardItem(_ item: ClipboardItem) {
        clipboardStore.writeToPasteboard(item)
        panelController.close()
        CommandPaletteController.shared.close()
        activatePreviousApp()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            PasteboardUtil.paste()
        }
    }

    func bootstrap() {
        floatingBall.onAction = { [weak self] action in
            self?.handle(action)
        }
        floatingBall.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
        dynamicIsland.onAction = { [weak self] action in
            self?.handle(action)
        }
        dynamicIsland.onOpenSettings = { [weak self] in
            self?.openSettings()
        }

        if showFloatingBall {
            floatingBall.show(size: settings.floatingBallSize)
        }
        if showDynamicIsland {
            dynamicIsland.show()
        }

        bindHotKeys()
        pasteboardMonitor.onNewItem = { [weak self] item in
            guard let self, !self.isClipboardPaused else { return }
            self.clipboardStore.add(item)
        }
        pasteboardMonitor.start()

        $showFloatingBall
            .dropFirst()
            .sink { [weak self] visible in
                guard let self else { return }
                self.settings.showFloatingBall = visible
                if visible {
                    self.floatingBall.show(size: self.settings.floatingBallSize)
                } else {
                    self.floatingBall.hide()
                }
            }
            .store(in: &cancellables)

        $showDynamicIsland
            .dropFirst()
            .sink { [weak self] visible in
                guard let self else { return }
                self.settings.showDynamicIsland = visible
                if visible {
                    self.dynamicIsland.show()
                } else {
                    self.dynamicIsland.hide()
                }
            }
            .store(in: &cancellables)
    }

    func teardown() {
        hotKeyManager.unregisterAll()
        pasteboardMonitor.stop()
        clipboardStore.flush()
        noteStore.flush()
        floatingBall.hide()
        dynamicIsland.hide()
        panelController.close()
        CommandPaletteController.shared.close()
        PinnedImageController.shared.closeAll()
    }

    func handle(_ action: ToolAction) {
        if action != .toggleDynamicIsland {
            dynamicIsland.collapse()
        }

        // Capture previous app before any UI that steals focus
        switch action {
        case .clipboard, .translate, .timestamp, .note, .commandPalette, .selectionTranslate, .settings:
            capturePreviousApp()
        default:
            break
        }

        switch action {
        case .screenshot:
            Task { await runCapture(.region) }
        case .screenshotFullscreen:
            Task { await runCapture(.fullscreen) }
        case .screenshotDelay:
            Task { await runCapture(.delayFullscreen) }
        case .screenshotWindow:
            Task { await runCapture(.windowUnderCursor) }
        case .screenshotLastRegion:
            Task { await runCapture(.lastRegion) }
        case .screenshotPreset:
            Task { await runCapture(.presetSize) }
        case .ocr:
            Task { await captureAndOCR() }
        case .clipboard:
            openPanel(.clipboard, title: "剪贴板")
        case .translate:
            openTranslate(text: pendingTranslateText.isEmpty ? nil : pendingTranslateText)
            pendingTranslateText = ""
        case .timestamp:
            openPanel(.timestamp, title: "时间戳")
        case .note:
            openPanel(.note, title: "笔记")
        case .colorPicker:
            pickColor()
        case .settings:
            openSettings()
        case .toggleFloatingBall:
            showFloatingBall.toggle()
        case .toggleDynamicIsland:
            showDynamicIsland.toggle()
        case .commandPalette:
            CommandPaletteController.shared.toggle()
        case .selectionTranslate:
            Task { await translateSelection() }
        }
    }

    func openSettings() {
        SettingsWindowController.shared.show()
    }

    func openTranslate(text: String?) {
        let initial = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        panelController.present(title: "翻译", size: ToolPanelKind.translate.preferredSize) {
            TranslateView(initialText: initial)
                .environmentObject(self)
        }
    }

    func translateSelection() async {
        guard let text = await SelectionHelper.selectedText(),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showToast("未获取到选中文本")
            return
        }
        openTranslate(text: text)
    }

    func showToast(_ message: String) {
        toastMessage = message
        ToastController.shared.show(message)
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    private func bindHotKeys() {
        hotKeyManager.unregisterAll()
        let map: [(SettingsStore.HotKeyID, ToolAction)] = [
            (.screenshot, .screenshot),
            (.screenshotFullscreen, .screenshotFullscreen),
            (.screenshotDelay, .screenshotDelay),
            (.screenshotWindow, .screenshotWindow),
            (.screenshotLastRegion, .screenshotLastRegion),
            (.screenshotPreset, .screenshotPreset),
            (.ocr, .ocr),
            (.clipboard, .clipboard),
            (.translate, .translate),
            (.timestamp, .timestamp),
            (.colorPicker, .colorPicker),
            (.toggleBall, .toggleFloatingBall),
            (.toggleIsland, .toggleDynamicIsland),
            (.commandPalette, .commandPalette),
            (.selectionTranslate, .selectionTranslate)
        ]
        for (id, action) in map {
            guard let chord = settings.hotKey(for: id) else { continue }
            hotKeyManager.register(chord, id: id.rawValue) { [weak self] in
                Task { @MainActor in
                    self?.handle(action)
                }
            }
        }
    }

    func reloadHotKeys() {
        // Always on main; protect against re-entrant Carbon calls during SwiftUI updates
        assert(Thread.isMainThread)
        bindHotKeys()
    }

    private func openPanel(_ kind: ToolPanelKind, title: String) {
        let view: AnyView
        switch kind {
        case .clipboard:
            view = AnyView(ClipboardView().environmentObject(self))
        case .translate:
            view = AnyView(TranslateView().environmentObject(self))
        case .timestamp:
            view = AnyView(TimestampView())
        case .note:
            view = AnyView(NoteView().environmentObject(self))
        case .settings:
            view = AnyView(SettingsView().environmentObject(self))
        }
        panelController.present(title: title, size: kind.preferredSize) {
            view
        }
    }

    /// 截图 / OCR / 取色时隐藏悬浮球与灵动岛避免入镜，结束后按需恢复。
    private func withBallHidden<T>(_ body: () async throws -> T) async rethrows -> T {
        let ballWasVisible = showFloatingBall
        let islandWasVisible = showDynamicIsland
        if ballWasVisible {
            floatingBall.hide()
        }
        if islandWasVisible {
            dynamicIsland.hide()
        }
        defer {
            if ballWasVisible, showFloatingBall {
                floatingBall.show(size: settings.floatingBallSize)
            }
            if islandWasVisible, showDynamicIsland {
                dynamicIsland.show()
            }
        }
        return try await body()
    }

    private func runCapture(_ mode: CaptureMode) async {
        await withBallHidden {
            panelController.close()
            CommandPaletteController.shared.close()

            do {
                guard let result = try await screenshotService.capture(mode) else {
                    showToast("已取消截图")
                    return
                }
                await handleCaptureResult(result)
            } catch {
                showToast("截图失败：\(error.localizedDescription)")
            }
        }
    }

    private func handleCaptureResult(_ result: CaptureResult) async {
        switch result.action {
        case .copy:
            PasteboardUtil.copyImage(result.image)
            showToast("截图已复制")
        case .edit:
            presentScreenshotEditor(result.image)
        case .pin:
            PinnedImageController.shared.pin(result.image)
            showToast("已钉在屏幕上")
        case .save:
            saveScreenshot(result.image)
        case .ocr:
            await runOCR(on: result.image)
        case .cancelled:
            showToast("已取消")
        }
    }

    private func presentScreenshotEditor(_ image: NSImage, strokes: [AnnotationStroke] = []) {
        ScreenshotEditorController.shared.present(
            image: image,
            initialStrokes: strokes,
            onCopy: { [weak self] result in
                PasteboardUtil.copyImage(result)
                self?.showToast("截图已复制")
            },
            onSave: { [weak self] result in
                self?.saveScreenshot(result)
            },
            onOCR: { [weak self] result in
                Task { await self?.runOCR(on: result) }
            },
            onPin: { [weak self] result in
                PinnedImageController.shared.pin(result)
                self?.showToast("已钉在屏幕上")
            },
            onCancel: { [weak self] in
                self?.showToast("已取消")
            }
        )
    }

    /// 继续上次未完成的截图编辑（若有草稿）。
    func resumeEditor() {
        guard let draft = EditorDraftStore.load() else {
            showToast("没有可继续的草稿")
            return
        }
        presentScreenshotEditor(draft.image, strokes: draft.strokes)
    }

    private func saveScreenshot(_ image: NSImage) {
        let defaultURL = settings.defaultScreenshotFileURL()
        // 快捷保存：默认路径直接写，避免 accessory app 下 SavePanel 无焦点
        if FileManager.default.fileExists(atPath: defaultURL.deletingLastPathComponent().path)
            || ((try? FileManager.default.createDirectory(at: defaultURL.deletingLastPathComponent(), withIntermediateDirectories: true)) != nil) {
            // 若用户偏好「每次选路径」可改；v0.5 默认静默保存到配置目录
            do {
                try ScreenshotExport.savePNG(image, to: defaultURL)
                if settings.copyAfterSave {
                    PasteboardUtil.copyImage(image)
                }
                showToast("已保存 \(defaultURL.lastPathComponent)")
                if settings.openFinderAfterSave {
                    NSWorkspace.shared.activateFileViewerSelecting([defaultURL])
                }
                return
            } catch {
                // fall through to panel
            }
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = defaultURL.lastPathComponent
        panel.directoryURL = defaultURL.deletingLastPathComponent()
        panel.title = "保存截图"
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                do {
                    try ScreenshotExport.savePNG(image, to: url)
                    if self.settings.copyAfterSave {
                        PasteboardUtil.copyImage(image)
                    }
                    self.showToast("已保存")
                    if self.settings.openFinderAfterSave {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } catch {
                    self.showToast("保存失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func captureAndOCR() async {
        await withBallHidden {
            do {
                let image = try await screenshotService.captureRegion()
                guard let image else {
                    showToast("已取消截图")
                    return
                }
                await runOCR(on: image)
            } catch {
                showToast("OCR 失败：\(error.localizedDescription)")
            }
        }
    }

    private func runOCR(on image: NSImage) async {
        do {
            let text = try await ocrService.recognize(image: image)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                showToast("未识别到文字")
                return
            }
            PasteboardUtil.copyString(text)
            panelController.present(title: "OCR 结果", size: CGSize(width: 460, height: 420)) {
                OCRResultView(text: text)
                    .environmentObject(self)
            }
            showToast("OCR 完成，已复制")
        } catch {
            showToast("OCR 失败：\(error.localizedDescription)")
        }
    }

    private func pickColor() {
        let ballWasVisible = showFloatingBall
        let islandWasVisible = showDynamicIsland
        if ballWasVisible {
            floatingBall.hide()
        }
        if islandWasVisible {
            dynamicIsland.hide()
        }
        colorPickerService.pick { [weak self] color in
            guard let self else { return }
            if ballWasVisible, self.showFloatingBall {
                self.floatingBall.show(size: self.settings.floatingBallSize)
            }
            if islandWasVisible, self.showDynamicIsland {
                self.dynamicIsland.show()
            }
            guard let color else { return }
            let hex = color.hexString
            PasteboardUtil.copyString(hex)
            self.panelController.present(title: "取色", size: CGSize(width: 380, height: 460)) {
                ColorPickerResultView(color: color)
            }
            self.showToast("已复制 \(hex)")
        }
    }
}

enum ToolAction: String, CaseIterable, Identifiable {
    case screenshot
    case screenshotFullscreen
    case screenshotDelay
    case screenshotWindow
    case screenshotLastRegion
    case screenshotPreset
    case ocr
    case clipboard
    case translate
    case timestamp
    case note
    case colorPicker
    case settings
    case toggleFloatingBall
    case toggleDynamicIsland
    case commandPalette
    case selectionTranslate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenshot: String(localized: "截图")
        case .screenshotFullscreen: String(localized: "全屏截图")
        case .screenshotDelay: String(localized: "延时全屏")
        case .screenshotWindow: String(localized: "光标下窗口")
        case .screenshotLastRegion: String(localized: "上次区域")
        case .screenshotPreset: String(localized: "预设尺寸")
        case .ocr: String(localized: "OCR")
        case .clipboard: String(localized: "剪贴板")
        case .translate: String(localized: "翻译")
        case .timestamp: String(localized: "时间戳")
        case .note: String(localized: "笔记")
        case .colorPicker: String(localized: "取色")
        case .settings: String(localized: "设置")
        case .toggleFloatingBall: String(localized: "悬浮球")
        case .toggleDynamicIsland: String(localized: "灵动岛")
        case .commandPalette: String(localized: "命令面板")
        case .selectionTranslate: String(localized: "划词翻译")
        }
    }

    var systemImage: String {
        switch self {
        case .screenshot: "camera.viewfinder"
        case .screenshotFullscreen: "rectangle.inset.filled"
        case .screenshotDelay: "timer"
        case .screenshotWindow: "macwindow"
        case .screenshotLastRegion: "arrow.uturn.backward.square"
        case .screenshotPreset: "aspectratio"
        case .ocr: "text.viewfinder"
        case .clipboard: "clipboard"
        case .translate: "globe"
        case .timestamp: "clock.arrow.circlepath"
        case .note: "note.text"
        case .colorPicker: "eyedropper"
        case .settings: "gearshape"
        case .toggleFloatingBall: "circle.dashed"
        case .toggleDynamicIsland: "capsule"
        case .commandPalette: "command"
        case .selectionTranslate: "character.cursor.ibeam"
        }
    }

    static var launcherItems: [ToolAction] {
        [.screenshot, .ocr, .clipboard, .note, .translate, .timestamp, .colorPicker]
    }
}

enum ToolPanelKind {
    case clipboard, translate, timestamp, note, settings

    var preferredSize: CGSize {
        switch self {
        case .clipboard: CGSize(width: 420, height: 540)
        case .translate: CGSize(width: 560, height: 500)
        case .timestamp: CGSize(width: 400, height: 520)
        case .note: CGSize(width: 640, height: 560)
        case .settings: CGSize(width: 520, height: 480)
        }
    }
}
