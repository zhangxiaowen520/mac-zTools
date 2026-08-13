import AppKit
import SwiftUI

@MainActor
final class FloatingBallController: NSObject {
    var onAction: ((ToolAction) -> Void)?
    var onOpenSettings: (() -> Void)?

    private var panel: NSPanel?
    private var menuPanel: NSPanel?
    private var ballSize: CGFloat = 52
    private var localMonitor: Any?
    private var rightClickMonitor: Any?
    private var spaceObserver: NSObjectProtocol?
    private var appearanceTimer: Timer?
    private var ballOpacity: Double = 1

    func show(size: CGFloat) {
        ballSize = size
        let panelSize = size + 18
        if panel == nil {
            createBallPanel(panelSize: panelSize)
        } else {
            panel?.setContentSize(NSSize(width: panelSize, height: panelSize))
            refreshHosting()
        }
        startAppearanceWatch()
        installRightClickMonitor()
        positionIfNeeded()
        updateAppearance()
        panel?.orderFrontRegardless()
    }

    func hide() {
        dismissMenu()
        stopAppearanceWatch()
        removeRightClickMonitor()
        panel?.orderOut(nil)
    }

    func updateSize(_ size: CGFloat) {
        ballSize = size
        let panelSize = size + 18
        panel?.setContentSize(NSSize(width: panelSize, height: panelSize))
        refreshHosting()
    }

    private func refreshHosting() {
        guard let panel else { return }
        let root = FloatingBallView(
            size: ballSize,
            opacity: ballOpacity,
            onTap: { [weak self] in self?.toggleMenu() },
            onDrag: { [weak self] translation in self?.moveBall(by: translation) },
            onDragEnded: { [weak self] in self?.handleDragEnd() }
        )
        panel.contentView = NSHostingView(rootView: root)
        panel.alphaValue = ballOpacity
    }

    private func createBallPanel(panelSize: CGFloat) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelSize, height: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        self.panel = panel
        refreshHosting()
    }

    private func installRightClickMonitor() {
        removeRightClickMonitor()
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseUp) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.window === panel || panel.frame.contains(NSEvent.mouseLocation) {
                Task { @MainActor in self.showContextMenu() }
                return nil
            }
            return event
        }
    }

    private func removeRightClickMonitor() {
        if let rightClickMonitor {
            NSEvent.removeMonitor(rightClickMonitor)
            self.rightClickMonitor = nil
        }
    }

    private func startAppearanceWatch() {
        stopAppearanceWatch()
        appearanceTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateAppearance() }
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateAppearance() }
        }
    }

    private func stopAppearanceWatch() {
        appearanceTimer?.invalidate()
        appearanceTimer = nil
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
            self.spaceObserver = nil
        }
        removeRightClickMonitor()
    }

    private func updateAppearance() {
        guard let panel, AppState.shared.showFloatingBall else { return }
        let settings = AppState.shared.settings
        let hideFS = settings.hideBallInFullscreen
        let dimEdge = settings.dimBallNearEdge

        if hideFS, isFrontAppFullscreen() {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }

        if !panel.isVisible {
            panel.orderFrontRegardless()
        }

        var opacity: Double = 1
        if dimEdge, let screen = panel.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            let frame = panel.frame
            let edge: CGFloat = 28
            let nearLeft = frame.minX <= visible.minX + edge
            let nearRight = frame.maxX >= visible.maxX - edge
            if nearLeft || nearRight {
                opacity = 0.42
            }
        }
        if abs(ballOpacity - opacity) > 0.01 {
            ballOpacity = opacity
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                panel.animator().alphaValue = opacity
            }
            // 不频繁重建 hosting，只改 alpha
        }
    }

    private func isFrontAppFullscreen() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let pid = front.processIdentifier
        for info in infoList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else { continue }
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let w = bounds["Width"] ?? 0
            let h = bounds["Height"] ?? 0
            guard let screen = NSScreen.main else { continue }
            if w >= screen.frame.width - 2 && h >= screen.frame.height - 2 {
                return true
            }
        }
        return false
    }

    private func positionIfNeeded() {
        guard let panel else { return }
        if let saved = BallPositionStore.load() {
            panel.setFrameOrigin(saved)
            return
        }
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let s = panel.frame.size.width
            panel.setFrameOrigin(CGPoint(
                x: visible.maxX - s - 18,
                y: visible.midY - s / 2
            ))
        }
    }

    private func moveBall(by translation: CGSize) {
        guard let panel else { return }
        let origin = CGPoint(
            x: panel.frame.origin.x + translation.width,
            y: panel.frame.origin.y - translation.height
        )
        panel.setFrameOrigin(origin)
    }

    private func handleDragEnd() {
        guard let panel else { return }
        var final = panel.frame.origin
        let snap = AppState.shared.settings.snapFloatingBall
        let s = panel.frame.size.width
        if snap, let screen = panel.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            let centerX = final.x + s / 2
            if centerX < visible.midX {
                final.x = visible.minX + 6
            } else {
                final.x = visible.maxX - s - 6
            }
            final.y = min(max(final.y, visible.minY + 6), visible.maxY - s - 6)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                panel.animator().setFrameOrigin(final)
            } completionHandler: {
                BallPositionStore.save(panel.frame.origin)
                Task { @MainActor in self.updateAppearance() }
            }
        } else {
            BallPositionStore.save(final)
            updateAppearance()
        }
    }

    private func toggleMenu() {
        if menuPanel?.isVisible == true {
            dismissMenu()
            return
        }
        presentMenu()
    }

    private func dismissMenu() {
        menuPanel?.orderOut(nil)
        menuPanel = nil
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func presentMenu() {
        guard let ball = panel else { return }
        dismissMenu()

        let size = CGSize(width: 248, height: 320)
        let menuPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        menuPanel.level = .statusBar
        menuPanel.isOpaque = false
        menuPanel.backgroundColor = .clear
        menuPanel.hasShadow = true
        menuPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = FloatingBallMenuView { [weak self] action in
            self?.dismissMenu()
            self?.onAction?(action)
        }
        menuPanel.contentView = NSHostingView(rootView: content)

        let ballFrame = ball.frame
        var origin = CGPoint(x: ballFrame.midX - size.width / 2, y: ballFrame.minY - size.height - 8)
        if let screen = ball.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            if origin.y < visible.minY {
                origin.y = ballFrame.maxY + 8
            }
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        }
        menuPanel.setFrameOrigin(origin)
        menuPanel.orderFrontRegardless()
        self.menuPanel = menuPanel

        localMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let loc = NSEvent.mouseLocation
                guard let menu = self.menuPanel else { return }
                if menu.frame.contains(loc) { return }
                if let ball = self.panel, ball.frame.contains(loc) { return }
                self.dismissMenu()
            }
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettingsAction), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let hideItem = NSMenuItem(title: "隐藏悬浮球", action: #selector(hideBallAction), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func openSettingsAction() {
        onOpenSettings?()
    }

    @objc private func hideBallAction() {
        onAction?(.toggleFloatingBall)
    }
}

enum BallPositionStore {
    private static let xKey = "settings.ballPositionX"
    private static let yKey = "settings.ballPositionY"

    static func load() -> CGPoint? {
        let d = UserDefaults.standard
        guard d.object(forKey: xKey) != nil else { return nil }
        return CGPoint(x: d.double(forKey: xKey), y: d.double(forKey: yKey))
    }

    static func save(_ point: CGPoint) {
        let d = UserDefaults.standard
        d.set(point.x, forKey: xKey)
        d.set(point.y, forKey: yKey)
    }
}

private struct FloatingBallView: View {
    let size: CGFloat
    var opacity: Double = 1
    let onTap: () -> Void
    let onDrag: (CGSize) -> Void
    let onDragEnded: () -> Void

    @State private var lastTranslation: CGSize = .zero
    @State private var isPressed = false
    @State private var dragged = false
    @State private var isHovering = false

    var body: some View {
        ZStack {
            ZToolsLogoMark(size: size, showGlow: true)
                .scaleEffect(isPressed ? 0.92 : (isHovering ? 1.04 : 1.0))
                .shadow(color: Color(red: 0.5, green: 0.2, blue: 0.9).opacity(isHovering ? 0.45 : 0.28), radius: isHovering ? 16 : 10, y: 4)
        }
        .frame(width: size + 18, height: size + 18)
        .contentShape(Circle())
        .opacity(isHovering ? 1 : opacity)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if abs(value.translation.width) + abs(value.translation.height) > 4 {
                        dragged = true
                    }
                    let delta = CGSize(
                        width: value.translation.width - lastTranslation.width,
                        height: value.translation.height - lastTranslation.height
                    )
                    lastTranslation = value.translation
                    if dragged {
                        onDrag(delta)
                    }
                }
                .onEnded { _ in
                    if dragged {
                        onDragEnded()
                    } else {
                        withAnimation(.easeOut(duration: 0.08)) { isPressed = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
                            withAnimation(.easeOut(duration: 0.12)) { isPressed = false }
                            onTap()
                        }
                    }
                    lastTranslation = .zero
                    dragged = false
                }
        )
    }
}

struct FloatingBallMenuView: View {
    let onSelect: (ToolAction) -> Void
    @ObservedObject private var settings = AppState.shared.settings
    private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                ZToolsLogoBadge()
                Spacer()
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ToolAction.launcherItems) { action in
                    Button {
                        onSelect(action)
                    } label: {
                        VStack(spacing: 5) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.accentColor.opacity(0.18),
                                                Color.accentColor.opacity(0.08)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 40, height: 40)
                                Image(systemName: action.systemImage)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.55, green: 0.45, blue: 1.0),
                                                Color(red: 0.95, green: 0.35, blue: 0.65)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                            Text(action.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.primary)
                            if let shortcut = shortcutLabel(for: action) {
                                Text(shortcut)
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(helpText(for: action))
                }
            }
        }
        .padding(14)
        .frame(width: 248, height: 320)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
    }

    private func shortcutLabel(for action: ToolAction) -> String? {
        guard let id = SettingsStore.HotKeyID.matching(toolAction: action.rawValue),
              let chord = settings.hotKey(for: id) else { return nil }
        return chord.displayString
    }

    private func helpText(for action: ToolAction) -> String {
        if let s = shortcutLabel(for: action) {
            return "\(action.title)  \(s)"
        }
        return action.title
    }
}
