import AppKit
import ApplicationServices
import ScreenCaptureKit

enum PermissionHelper {
    static var hasScreenRecordingPreflight: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 仅在用户主动点「请求权限」时调用，避免截图流程里反复弹窗。
    @discardableResult
    static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func canAccessScreenContent() async -> Bool {
        // 1) 先试 SCK —— 这是最终标准
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            if !content.displays.isEmpty { return true }
        } catch {
            // continue
        }
        // 2) preflight 仅作参考
        return CGPreflightScreenCaptureAccess()
    }

    static var hasAccessibility: Bool {
        if AXIsProcessTrusted() { return true }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// 运行时探测：不先依赖 hasAccessibility 布尔值（ad-hoc 有时布尔为 false 但开关已开）。
    static func probeAccessibility() -> Bool {
        if hasAccessibility { return true }
        // 直接试系统级 AX；若返回 apiDisabled 则确实无权限
        let system = AXUIElementCreateSystemWide()
        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &ref)
        switch err {
        case .success, .noValue, .attributeUnsupported:
            return true
        default:
            // 再试一次 trusted（用户可能刚打开开关）
            return AXIsProcessTrusted()
        }
    }

    /// 设置页展示用：综合布尔 + 探测
    static var accessibilityStatusOK: Bool {
        hasAccessibility || probeAccessibility()
    }

    static func requestAccessibilityPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openScreenRecordingSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    static func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    /// 当前进程可执行文件路径（用于设置页展示）
    static var runningAppPath: String {
        Bundle.main.bundlePath
    }
}
