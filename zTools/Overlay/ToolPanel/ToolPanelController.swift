import AppKit
import SwiftUI

/// Borderless / nonactivating panels need this to accept text input.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ToolPanelController {
    private var panel: KeyablePanel?
    private var escMonitor: Any?
    private var clickMonitor: Any?

    var isVisible: Bool { panel?.isVisible == true }

    func present<Content: View>(title: String, size: CGSize, @ViewBuilder content: () -> Content) {
        close()
        AppState.shared.capturePreviousApp()

        // 无系统标题栏，避免红绿灯/标题漂在内容外
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
        // 必须为 false：否则会抢走 TextField 点击，导致无法聚焦/输入
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = false
        panel.acceptsMouseMovedEvents = true

        let root = ToolPanelChrome(
            title: title,
            onClose: { [weak self] in self?.close(restorePreviousApp: true) },
            onDragWindow: { [weak panel] delta in
                guard let panel else { return }
                var origin = panel.frame.origin
                origin.x += delta.width
                origin.y -= delta.height
                panel.setFrameOrigin(origin)
            }
        ) {
            content()
        }
        .frame(width: size.width, height: size.height)

        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        panel.setContentSize(size)
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 14
        panel.contentView?.layer?.masksToBounds = true

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let origin = CGPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2 + 40
            )
            panel.setFrameOrigin(origin)
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel

        DispatchQueue.main.async { [weak panel, weak hosting] in
            panel?.makeKey()
            panel?.makeFirstResponder(hosting)
            Self.focusFirstTextInput(in: hosting)
        }
        // 再延迟一帧，确保 SwiftUI 文本控件已挂载
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak panel, weak hosting] in
            panel?.makeKey()
            Self.focusFirstTextInput(in: hosting)
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
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil

        if restorePreviousApp {
            AppState.shared.activatePreviousApp()
        }
    }

    private static func focusFirstTextInput(in view: NSView?) {
        guard let view else { return }
        if let field = view as? NSTextField, field.isEditable {
            view.window?.makeFirstResponder(field)
            return
        }
        if let textView = view as? NSTextView, textView.isEditable {
            view.window?.makeFirstResponder(textView)
            return
        }
        for sub in view.subviews {
            focusFirstTextInput(in: sub)
            if view.window?.firstResponder is NSText || view.window?.firstResponder is NSTextField {
                return
            }
        }
    }
}

struct ToolPanelChrome<Content: View>: View {
    let title: String
    let onClose: () -> Void
    var onDragWindow: ((CGSize) -> Void)? = nil
    @ViewBuilder let content: Content

    @State private var lastDrag: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onClose) {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.38, blue: 0.35))
                        .frame(width: 12, height: 12)
                        .help("关闭 (Esc)")
                }
                .buttonStyle(.plain)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .help("关闭 (Esc)")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let delta = CGSize(
                            width: value.translation.width - lastDrag.width,
                            height: value.translation.height - lastDrag.height
                        )
                        lastDrag = value.translation
                        onDragWindow?(delta)
                    }
                    .onEnded { _ in lastDrag = .zero }
            )

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.06),
                            Color.black.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
        .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
    }
}

@MainActor
final class ToastController {
    static let shared = ToastController()
    private var panel: NSPanel?

    func show(_ message: String) {
        panel?.orderOut(nil)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = ToastView(message: message)
        panel.contentView = NSHostingView(rootView: view)

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let size = CGSize(width: 280, height: 40)
            panel.setFrame(
                CGRect(
                    x: visible.midX - size.width / 2,
                    y: visible.minY + 48,
                    width: size.width,
                    height: size.height
                ),
                display: true
            )
        }
        panel.orderFrontRegardless()
        self.panel = panel

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel = nil
        }
    }
}

private struct ToastView: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
            .padding(4)
    }
}
