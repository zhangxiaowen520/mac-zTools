import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    enum HotKeyID: String, CaseIterable, Identifiable {
        case screenshot
        case screenshotFullscreen, screenshotDelay, screenshotWindow, screenshotLastRegion, screenshotPreset
        case ocr, clipboard, translate, timestamp, note, colorPicker, toggleBall
        case commandPalette, selectionTranslate

        var id: String { rawValue }

        var title: String {
            switch self {
            case .screenshot: String(localized: "截图（选区）")
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
            case .toggleBall: String(localized: "显示/隐藏悬浮球")
            case .commandPalette: String(localized: "命令面板")
            case .selectionTranslate: String(localized: "划词翻译")
            }
        }

        static var screenshotKeys: [HotKeyID] {
            [.screenshot, .screenshotFullscreen, .screenshotDelay, .screenshotWindow, .screenshotLastRegion, .screenshotPreset]
        }

        /// Map tool actions to hotkey ids for UI shortcut labels.
        static func matching(toolAction raw: String) -> HotKeyID? {
            switch raw {
            case "screenshot": return .screenshot
            case "screenshotFullscreen": return .screenshotFullscreen
            case "screenshotDelay": return .screenshotDelay
            case "screenshotWindow": return .screenshotWindow
            case "screenshotLastRegion": return .screenshotLastRegion
            case "screenshotPreset": return .screenshotPreset
            case "ocr": return .ocr
            case "clipboard": return .clipboard
            case "translate": return .translate
            case "timestamp": return .timestamp
            case "note": return .note
            case "colorPicker": return .colorPicker
            case "toggleFloatingBall": return .toggleBall
            case "commandPalette": return .commandPalette
            case "selectionTranslate": return .selectionTranslate
            default: return nil
            }
        }
    }

    private let defaults = UserDefaults.standard
    private let keychain = KeychainStore(service: "com.zeno.ztools")

    @Published var showFloatingBall: Bool {
        didSet { defaults.set(showFloatingBall, forKey: Keys.showFloatingBall) }
    }

    @Published var floatingBallSize: CGFloat {
        didSet { defaults.set(Double(floatingBallSize), forKey: Keys.floatingBallSize) }
    }

    @Published var snapFloatingBall: Bool {
        didSet { defaults.set(snapFloatingBall, forKey: Keys.snapFloatingBall) }
    }

    @Published var hideBallInFullscreen: Bool {
        didSet { defaults.set(hideBallInFullscreen, forKey: Keys.hideBallInFullscreen) }
    }

    @Published var dimBallNearEdge: Bool {
        didSet { defaults.set(dimBallNearEdge, forKey: Keys.dimBallNearEdge) }
    }

    @Published var clipboardLimit: Int {
        didSet { defaults.set(clipboardLimit, forKey: Keys.clipboardLimit) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            LaunchAtLogin.setEnabled(launchAtLogin)
        }
    }

    @Published var screenshotSaveDirectory: String {
        didSet { defaults.set(screenshotSaveDirectory, forKey: Keys.screenshotSaveDirectory) }
    }

    @Published var openFinderAfterSave: Bool {
        didSet { defaults.set(openFinderAfterSave, forKey: Keys.openFinderAfterSave) }
    }

    @Published var copyAfterSave: Bool {
        didSet { defaults.set(copyAfterSave, forKey: Keys.copyAfterSave) }
    }

    @Published var aiBaseURL: String {
        didSet { defaults.set(aiBaseURL, forKey: Keys.aiBaseURL) }
    }

    @Published var aiModel: String {
        didSet { defaults.set(aiModel, forKey: Keys.aiModel) }
    }

    @Published var targetLanguage: String {
        didSet { defaults.set(targetLanguage, forKey: Keys.targetLanguage) }
    }

    @Published var apiKey: String {
        didSet { try? keychain.set(apiKey, for: Keys.apiKey) }
    }

    @Published var hotKeys: [String: KeyChord] {
        didSet { saveHotKeys() }
    }

    init() {
        showFloatingBall = defaults.object(forKey: Keys.showFloatingBall) as? Bool ?? true
        floatingBallSize = CGFloat(defaults.object(forKey: Keys.floatingBallSize) as? Double ?? 52)
        snapFloatingBall = defaults.object(forKey: Keys.snapFloatingBall) as? Bool ?? true
        hideBallInFullscreen = defaults.object(forKey: Keys.hideBallInFullscreen) as? Bool ?? true
        dimBallNearEdge = defaults.object(forKey: Keys.dimBallNearEdge) as? Bool ?? true
        clipboardLimit = defaults.object(forKey: Keys.clipboardLimit) as? Int ?? 100
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        openFinderAfterSave = defaults.object(forKey: Keys.openFinderAfterSave) as? Bool ?? true
        copyAfterSave = defaults.object(forKey: Keys.copyAfterSave) as? Bool ?? false
        aiBaseURL = defaults.string(forKey: Keys.aiBaseURL) ?? "https://api.deepseek.com/v1"
        aiModel = defaults.string(forKey: Keys.aiModel) ?? "deepseek-chat"
        targetLanguage = defaults.string(forKey: Keys.targetLanguage) ?? "zh"
        apiKey = (try? keychain.get(Keys.apiKey)) ?? ""

        if let saved = defaults.string(forKey: Keys.screenshotSaveDirectory), !saved.isEmpty {
            screenshotSaveDirectory = saved
        } else {
            screenshotSaveDirectory = Self.defaultSaveDirectory.path
        }

        // 快捷键方案版本：变更默认布局时递增，自动套用新默认
        // 注意：init 内赋值不会触发 didSet，必须在全部属性初始化后手动写入 UserDefaults
        let scheme = defaults.integer(forKey: Keys.hotKeysScheme)
        if scheme < Self.currentHotKeysScheme {
            hotKeys = Self.defaultHotKeys
        } else {
            var loaded = Self.loadHotKeys(from: defaults) ?? [:]
            for (k, v) in Self.defaultHotKeys where loaded[k] == nil {
                loaded[k] = v
            }
            hotKeys = loaded.isEmpty ? Self.defaultHotKeys : loaded
        }
        // 全部 stored properties 已初始化，可安全写盘
        let encoded = hotKeys.mapValues { $0.storageValue }
        defaults.set(encoded, forKey: Keys.hotKeys)
        if scheme < Self.currentHotKeysScheme {
            defaults.set(Self.currentHotKeysScheme, forKey: Keys.hotKeysScheme)
        }
        defaults.synchronize()
    }

    var screenshotSaveDirectoryURL: URL {
        URL(fileURLWithPath: screenshotSaveDirectory, isDirectory: true)
    }

    func defaultScreenshotFileURL() -> URL {
        let dir = screenshotSaveDirectoryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return dir.appendingPathComponent("zTools_\(formatter.string(from: Date())).png")
    }

    func hotKey(for id: HotKeyID) -> KeyChord? {
        hotKeys[id.rawValue]
    }

    /// 检测 chord 是否与其它功能冲突，返回冲突的功能 id（无冲突返回 nil）。
    func conflictingID(for chord: KeyChord?, excluding id: HotKeyID) -> HotKeyID? {
        guard let chord else { return nil }
        for (key, value) in hotKeys where key != id.rawValue {
            if value == chord, let conflict = HotKeyID(rawValue: key) {
                return conflict
            }
        }
        return nil
    }

    /// 设置快捷键；若与其它功能冲突则拒绝并返回冲突 id，成功返回 nil。
    @discardableResult
    func setHotKey(_ chord: KeyChord?, for id: HotKeyID) -> HotKeyID? {
        var next = hotKeys
        if let chord {
            if let conflict = conflictingID(for: chord, excluding: id) {
                return conflict
            }
            next[id.rawValue] = chord
        } else {
            next.removeValue(forKey: id.rawValue)
        }
        hotKeys = next
        return nil
    }

    func resetHotKeys() {
        hotKeys = Self.defaultHotKeys
        defaults.set(Self.currentHotKeysScheme, forKey: Keys.hotKeysScheme)
    }

    /// 递增后会在下次启动用新默认快捷键覆盖旧方案
    private static let currentHotKeysScheme = 4

    private func saveHotKeys() {
        let encoded = hotKeys.mapValues { $0.storageValue }
        defaults.set(encoded, forKey: Keys.hotKeys)
    }

    private static func loadHotKeys(from defaults: UserDefaults) -> [String: KeyChord]? {
        guard let raw = defaults.dictionary(forKey: Keys.hotKeys) as? [String: String] else {
            return nil
        }
        var result: [String: KeyChord] = [:]
        for (key, value) in raw {
            if let chord = KeyChord(storageValue: value) {
                result[key] = chord
            }
        }
        return result.isEmpty ? nil : result
    }

    private static var defaultHotKeys: [String: KeyChord] {
        // 默认以 ⌥ + 单键（两键）为主，降低操作成本
        [
            HotKeyID.screenshot.rawValue: KeyChord(keyCode: 0, modifiers: [.option]), // ⌥A 选区
            HotKeyID.screenshotFullscreen.rawValue: KeyChord(keyCode: 3, modifiers: [.option]), // ⌥F 全屏
            HotKeyID.screenshotDelay.rawValue: KeyChord(keyCode: 2, modifiers: [.option]), // ⌥D 延时
            HotKeyID.screenshotWindow.rawValue: KeyChord(keyCode: 6, modifiers: [.option]), // ⌥Z 窗口
            HotKeyID.screenshotLastRegion.rawValue: KeyChord(keyCode: 7, modifiers: [.option]), // ⌥X 上次
            HotKeyID.screenshotPreset.rawValue: KeyChord(keyCode: 5, modifiers: [.option]), // ⌥G 预设
            HotKeyID.ocr.rawValue: KeyChord(keyCode: 31, modifiers: [.option]), // ⌥O
            HotKeyID.clipboard.rawValue: KeyChord(keyCode: 9, modifiers: [.option]), // ⌥V
            HotKeyID.translate.rawValue: KeyChord(keyCode: 17, modifiers: [.option]), // ⌥T
            HotKeyID.timestamp.rawValue: KeyChord(keyCode: 32, modifiers: [.option]), // ⌥U
            HotKeyID.note.rawValue: KeyChord(keyCode: 45, modifiers: [.option]), // ⌥N
            HotKeyID.colorPicker.rawValue: KeyChord(keyCode: 8, modifiers: [.option]), // ⌥C
            HotKeyID.toggleBall.rawValue: KeyChord(keyCode: 11, modifiers: [.option]), // ⌥B 悬浮球
            HotKeyID.commandPalette.rawValue: KeyChord(keyCode: 40, modifiers: [.option]), // ⌥K
            HotKeyID.selectionTranslate.rawValue: KeyChord(keyCode: 14, modifiers: [.option]) // ⌥E 划词译
        ]
    }

    static var defaultSaveDirectory: URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        return pictures.appendingPathComponent("zTools", isDirectory: true)
    }

    private enum Keys {
        static let showFloatingBall = "settings.showFloatingBall"
        static let floatingBallSize = "settings.floatingBallSize"
        static let snapFloatingBall = "settings.snapFloatingBall"
        static let hideBallInFullscreen = "settings.hideBallInFullscreen"
        static let dimBallNearEdge = "settings.dimBallNearEdge"
        static let clipboardLimit = "settings.clipboardLimit"
        static let launchAtLogin = "settings.launchAtLogin"
        static let screenshotSaveDirectory = "settings.screenshotSaveDirectory"
        static let openFinderAfterSave = "settings.openFinderAfterSave"
        static let copyAfterSave = "settings.copyAfterSave"
        static let aiBaseURL = "settings.aiBaseURL"
        static let aiModel = "settings.aiModel"
        static let targetLanguage = "settings.targetLanguage"
        static let apiKey = "settings.apiKey"
        static let hotKeys = "settings.hotKeys"
        static let hotKeysScheme = "settings.hotKeysScheme"
    }
}
