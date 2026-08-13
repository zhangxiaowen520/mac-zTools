import AppKit
import ApplicationServices

@MainActor
enum SelectionHelper {
    /// 读取当前焦点处选中文本（需辅助功能权限）
    static func selectedText() async -> String? {
        if !PermissionHelper.hasAccessibility {
            PermissionHelper.requestAccessibilityPrompt()
            return nil
        }

        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        if focusedStatus == .success, let focused = focusedRef {
            let element = (focused as! AXUIElement)
            var selectedRef: CFTypeRef?
            let selectedStatus = AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                &selectedRef
            )
            if selectedStatus == .success, let text = selectedRef as? String, !text.isEmpty {
                return text
            }
        }

        return await selectedTextViaClipboardFallback()
    }

    /// 模拟 ⌘C 读取选区
    private static func selectedTextViaClipboardFallback() async -> String? {
        let pb = NSPasteboard.general
        let previous = pb.string(forType: .string)
        let change = pb.changeCount

        AppState.shared.pasteboardMonitor.performInternalWrite {}

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        let deadline = Date().addingTimeInterval(0.35)
        while Date() < deadline {
            if pb.changeCount != change { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        let text = pb.string(forType: .string)
        if let previous {
            AppState.shared.pasteboardMonitor.performInternalWrite {
                pb.clearContents()
                pb.setString(previous, forType: .string)
            }
        }
        guard let text, !text.isEmpty else { return nil }
        return text
    }
}
