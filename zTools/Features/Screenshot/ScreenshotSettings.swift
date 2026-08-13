import AppKit
import Foundation
import SwiftUI

enum CaptureAfterAction: String, CaseIterable, Identifiable {
    case copy
    case edit
    case pin
    case save
    case ocr

    var id: String { rawValue }

    var title: String {
        switch self {
        case .copy: "复制到剪贴板"
        case .edit: "打开编辑器"
        case .pin: "钉图"
        case .save: "保存文件"
        case .ocr: "OCR 识别"
        }
    }
}

@MainActor
final class ScreenshotSettings: ObservableObject {
    static let shared = ScreenshotSettings()

    private let d = UserDefaults.standard

    @Published var showCrosshair: Bool {
        didSet { d.set(showCrosshair, forKey: Keys.crosshair) }
    }
    @Published var captureCursor: Bool {
        didSet { d.set(captureCursor, forKey: Keys.cursor) }
    }
    @Published var addShadow: Bool {
        didSet { d.set(addShadow, forKey: Keys.shadow) }
    }
    @Published var shadowRadius: Double {
        didSet { d.set(shadowRadius, forKey: Keys.shadowRadius) }
    }
    @Published var cornerRadius: Double {
        didSet { d.set(cornerRadius, forKey: Keys.cornerRadius) }
    }
    @Published var playSound: Bool {
        didSet { d.set(playSound, forKey: Keys.sound) }
    }
    @Published var defaultAction: CaptureAfterAction {
        didSet { d.set(defaultAction.rawValue, forKey: Keys.defaultAction) }
    }
    @Published var delaySeconds: Int {
        didSet { d.set(delaySeconds, forKey: Keys.delay) }
    }
    @Published var presetWidth: Int {
        didSet { d.set(presetWidth, forKey: Keys.presetW) }
    }
    @Published var presetHeight: Int {
        didSet { d.set(presetHeight, forKey: Keys.presetH) }
    }
    @Published var lastRegionX: Double {
        didSet { d.set(lastRegionX, forKey: Keys.lastX) }
    }
    @Published var lastRegionY: Double {
        didSet { d.set(lastRegionY, forKey: Keys.lastY) }
    }
    @Published var lastRegionW: Double {
        didSet { d.set(lastRegionW, forKey: Keys.lastW) }
    }
    @Published var lastRegionH: Double {
        didSet { d.set(lastRegionH, forKey: Keys.lastH) }
    }

    private init() {
        showCrosshair = d.object(forKey: Keys.crosshair) as? Bool ?? true
        captureCursor = d.object(forKey: Keys.cursor) as? Bool ?? false
        // 默认关闭阴影/圆角，避免重绘链路影响清晰度；需要装饰可在设置打开
        addShadow = d.object(forKey: Keys.shadow) as? Bool ?? false
        shadowRadius = d.object(forKey: Keys.shadowRadius) as? Double ?? 18
        cornerRadius = d.object(forKey: Keys.cornerRadius) as? Double ?? 0
        playSound = d.object(forKey: Keys.sound) as? Bool ?? true
        delaySeconds = d.object(forKey: Keys.delay) as? Int ?? 3
        presetWidth = d.object(forKey: Keys.presetW) as? Int ?? 800
        presetHeight = d.object(forKey: Keys.presetH) as? Int ?? 600
        lastRegionX = d.double(forKey: Keys.lastX)
        lastRegionY = d.double(forKey: Keys.lastY)
        lastRegionW = d.double(forKey: Keys.lastW)
        lastRegionH = d.double(forKey: Keys.lastH)
        if let raw = d.string(forKey: Keys.defaultAction),
           let action = CaptureAfterAction(rawValue: raw) {
            defaultAction = action
        } else {
            defaultAction = .copy
        }
    }

    var lastRegion: CGRect? {
        get {
            guard lastRegionW > 2, lastRegionH > 2 else { return nil }
            return CGRect(x: lastRegionX, y: lastRegionY, width: lastRegionW, height: lastRegionH)
        }
        set {
            if let r = newValue?.standardized {
                lastRegionX = r.origin.x
                lastRegionY = r.origin.y
                lastRegionW = r.width
                lastRegionH = r.height
            }
        }
    }

    private enum Keys {
        static let crosshair = "ss.crosshair"
        static let cursor = "ss.cursor"
        static let shadow = "ss.shadow"
        static let shadowRadius = "ss.shadowRadius"
        static let cornerRadius = "ss.cornerRadius"
        static let sound = "ss.sound"
        static let defaultAction = "ss.defaultAction"
        static let delay = "ss.delay"
        static let presetW = "ss.presetW"
        static let presetH = "ss.presetH"
        static let lastX = "ss.lastX"
        static let lastY = "ss.lastY"
        static let lastW = "ss.lastW"
        static let lastH = "ss.lastH"
    }
}

enum ScreenshotEffects {
    @MainActor
    static func apply(to image: NSImage, settings: ScreenshotSettings = .shared) -> NSImage {
        let corner = CGFloat(settings.cornerRadius)
        let shadowOn = settings.addShadow
        let shadowR = CGFloat(settings.shadowRadius)
        guard corner > 0.5 || shadowOn else { return image }

        let scale = RetinaImage.scale(of: image)
        let srcSize = image.size
        let pad = shadowOn ? shadowR * 1.6 : 0
        let outSize = NSSize(width: srcSize.width + pad * 2, height: srcSize.height + pad * 2)

        // 使用位图像素密度离屏绘制，避免 lockFocus 在 Retina 上掉到 1x 变糊
        return RetinaImage.render(sizePoints: outSize, scale: scale) { _, _ in
            let drawRect = CGRect(x: pad, y: pad, width: srcSize.width, height: srcSize.height)
            let path = NSBezierPath(roundedRect: drawRect, xRadius: corner, yRadius: corner)

            if shadowOn {
                let ctx = NSGraphicsContext.current?.cgContext
                ctx?.saveGState()
                ctx?.setShadow(
                    offset: CGSize(width: 0, height: -shadowR * 0.35),
                    blur: shadowR,
                    color: NSColor.black.withAlphaComponent(0.35).cgColor
                )
                NSColor.white.setFill()
                path.fill()
                ctx?.restoreGState()
            }

            NSGraphicsContext.current?.saveGraphicsState()
            path.addClip()
            // 按源图完整像素绘制
            image.draw(
                in: drawRect,
                from: CGRect(origin: .zero, size: srcSize),
                operation: .sourceOver,
                fraction: 1.0,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            NSGraphicsContext.current?.restoreGraphicsState()
        } ?? image
    }

    @MainActor
    static func playShutterIfNeeded() {
        guard ScreenshotSettings.shared.playSound else { return }
        NSSound(named: "Tink")?.play()
    }
}

enum WindowCaptureHelper {
    struct WinInfo {
        let id: CGWindowID
        let frame: CGRect // Cocoa global
        let name: String
        let pid: pid_t
    }

    /// 列出可截取窗口（Cocoa 坐标）
    static func listWindows() -> [WinInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var result: [WinInfo] = []
        for info in list {
            guard let num = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID else { continue }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let cg = CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )
            guard cg.width > 40, cg.height > 40 else { continue }
            let cocoa = ScreenCoordinate.convertCGRectToCocoa(cg)
            let name = (info[kCGWindowOwnerName as String] as? String) ?? "Window"
            result.append(WinInfo(id: num, frame: cocoa, name: name, pid: pid))
        }
        return result
    }

    static func windowUnderMouse() -> WinInfo? {
        let mouse = NSEvent.mouseLocation
        let wins = listWindows()
        // list is front-to-back
        return wins.first { $0.frame.contains(mouse) }
    }

    static func windowAtPoint(_ point: CGPoint) -> WinInfo? {
        listWindows().first { $0.frame.contains(point) }
    }
}

enum ScreenCoordinate {
    /// Cocoa 全局（左下原点）→ Quartz 全局（主屏左上原点，Y 向下）
    static func convertCocoaRectToCG(_ cocoaRect: CGRect) -> CGRect {
        let unionHeight = unionMaxY()
        return CGRect(
            x: cocoaRect.origin.x,
            y: unionHeight - cocoaRect.origin.y - cocoaRect.height,
            width: cocoaRect.width,
            height: cocoaRect.height
        )
    }

    /// Quartz 全局（Y 向下）→ Cocoa 全局（Y 向上）
    static func convertCGRectToCocoa(_ cgRect: CGRect) -> CGRect {
        let unionHeight = unionMaxY()
        return CGRect(
            x: cgRect.origin.x,
            y: unionHeight - cgRect.origin.y - cgRect.height,
            width: cgRect.width,
            height: cgRect.height
        )
    }

    /// 所有屏幕 union 的顶部（Cocoa 坐标）。副屏排在主屏上方/偏移时，
    /// 必须用 union 而非主屏高度做参考，否则截图区域会错位。
    private static func unionMaxY() -> CGFloat {
        let screens = NSScreen.screens
        guard let first = screens.first else {
            return CGDisplayBounds(CGMainDisplayID()).height
        }
        var union = first.frame
        for screen in screens.dropFirst() {
            union = union.union(screen.frame)
        }
        return union.maxY
    }
}
