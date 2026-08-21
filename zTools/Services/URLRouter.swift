import AppKit
import Foundation

/// 处理 ztools:// URL
/// 示例：
/// - ztools://screenshot
/// - ztools://ocr
/// - ztools://clipboard
/// - ztools://translate?text=hello
/// - ztools://timestamp
/// - ztools://color
/// - ztools://palette
/// - ztools://settings
/// - ztools://selection-translate
enum URLRouter {
    static let scheme = "ztools"

    @MainActor
    static func handle(_ url: URL) {
        guard url.scheme?.lowercased() == scheme else { return }
        let host = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary(uniqueKeysWithValues: (comps?.queryItems ?? []).compactMap { item -> (String, String)? in
            guard let v = item.value else { return nil }
            return (item.name.lowercased(), v)
        })

        let state = AppState.shared

        switch host {
        case "screenshot", "capture", "region":
            state.handle(.screenshot)
        case "fullscreen":
            state.handle(.screenshotFullscreen)
        case "delay", "delay-fullscreen":
            state.handle(.screenshotDelay)
        case "window", "window-under-cursor":
            state.handle(.screenshotWindow)
        case "last", "last-region":
            state.handle(.screenshotLastRegion)
        case "preset":
            state.handle(.screenshotPreset)
        case "ocr":
            state.handle(.ocr)
        case "clipboard", "pasteboard":
            state.handle(.clipboard)
        case "translate":
            if let text = query["text"], !text.isEmpty {
                state.openTranslate(text: text.removingPercentEncoding ?? text)
            } else {
                state.handle(.translate)
            }
        case "timestamp", "time":
            state.handle(.timestamp)
        case "note", "notes":
            state.handle(.note)
        case "color", "eyedropper", "pick-color":
            state.handle(.colorPicker)
        case "palette", "command":
            state.handle(.commandPalette)
        case "settings", "preferences":
            state.handle(.settings)
        case "selection-translate", "selection":
            state.handle(.selectionTranslate)
        case "toggle-ball":
            state.handle(.toggleFloatingBall)
        case "island", "toggle-island", "dynamic-island":
            state.handle(.toggleDynamicIsland)
        default:
            ToastController.shared.show("未知命令：\(host)")
        }
    }
}
