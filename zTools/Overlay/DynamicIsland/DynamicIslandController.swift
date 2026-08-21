import AppKit
import SwiftUI

private enum IslandHaptic {
    static func enter() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    static func expand() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .drawCompleted)
    }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var hitRectProvider: () -> CGRect = { .zero }

    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard hitRectProvider().contains(point) else { return nil }
        return super.hitTest(point)
    }
}

@MainActor
final class DynamicIslandController: NSObject {
    var onAction: ((ToolAction) -> Void)?
    var onOpenSettings: (() -> Void)?

    private let session = DynamicIslandSession()
    private var panel: IslandPanel?
    private var hoverWorkItem: DispatchWorkItem?
    private var collapseWorkItem: DispatchWorkItem?
    private var suppressHoverUntilExit = false
    private var globalMoveMonitor: Any?
    private var localMoveMonitor: Any?
    private var mouseDownMonitor: Any?
    private var keyMonitor: Any?
    private var rightClickMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var appearanceTimer: Timer?
    private var lastMoveAt: TimeInterval = 0
    private var pointerInside = false

    func show() {
        if panel == nil {
            createPanel()
        }
        startWatching()
        updateAppearance()
        panel?.orderFrontRegardless()
        reposition()
        if session.isLocked {
            session.isExpanded = true
        }
        applyMousePolicy()
    }

    func hide() {
        cancelPending()
        if !session.isLocked {
            session.isExpanded = false
        }
        applyMousePolicy()
        stopWatching()
        panel?.orderOut(nil)
    }

    func collapse() {
        cancelPending()
        setExpanded(false)
    }

    private func createPanel() {
        let metrics = metricsForPreferredScreen()
        session.metrics = metrics
        let size = metrics.windowSize

        let panel = IslandPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.acceptsMouseMovedEvents = true
        panel.sharingType = .none
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true

        let root = DynamicIslandView(
            session: session,
            onTap: { [weak self] in self?.handleTap() },
            onSelect: { [weak self] action in
                self?.dismissThen { self?.onAction?(action) }
            },
            onOpenSettings: { [weak self] in
                self?.dismissThen { self?.onOpenSettings?() }
            },
            onLaunchApp: { [weak self] url in
                self?.dismissThen { NSWorkspace.shared.open(url) }
            },
            onToggleLock: { [weak self] in self?.toggleLock() }
        )
        let hosting = IslandHostingView(rootView: root)
        hosting.safeAreaRegions = []
        hosting.hitRectProvider = { [weak self] in
            guard let self else { return .zero }
            return self.session.metrics.hitRect(
                expanded: self.session.isExpanded,
                height: self.session.isExpanded ? self.session.tab.islandHeight : nil
            )
        }
        panel.contentView = hosting
        self.panel = panel
        place(panel, metrics: metrics, on: preferredScreen())
    }

    private func reposition() {
        guard let panel else { return }
        let metrics = metricsForPreferredScreen()
        session.metrics = metrics
        let size = metrics.windowSize
        if panel.frame.size != size {
            panel.setContentSize(size)
        }
        place(panel, metrics: metrics, on: preferredScreen())
    }

    private func place(_ panel: IslandPanel, metrics: IslandMetrics, on screen: NSScreen?) {
        guard let screen else { return }
        let frame = screen.frame
        panel.setFrame(
            NSRect(
                x: frame.minX,
                y: frame.maxY - metrics.windowSize.height + 1,
                width: metrics.windowSize.width,
                height: metrics.windowSize.height
            ),
            display: true
        )
    }

    private func preferredScreen() -> NSScreen? {
        let notched = NSScreen.screens.filter { screen in
            screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
        }
        if let main = NSScreen.main, notched.contains(where: { $0 === main }) {
            return main
        }
        return notched.first ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func metricsForPreferredScreen() -> IslandMetrics {
        let screen = preferredScreen()
        let frame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let visible = screen?.visibleFrame ?? frame
        let safeTop = screen?.safeAreaInsets.top ?? 0
        var notchWidth: CGFloat = 0
        var notchHeight: CGFloat = 0
        var notchMidX = frame.width / 2
        if let left = screen?.auxiliaryTopLeftArea, let right = screen?.auxiliaryTopRightArea {
            let minX = left.maxX - frame.minX
            let maxX = right.minX - frame.minX
            notchWidth = max(0, maxX - minX)
            notchHeight = left.height
            notchMidX = (minX + maxX) / 2
        }
        return IslandMetrics.make(
            screenWidth: frame.width,
            visibleTopInset: frame.maxY - visible.maxY,
            safeAreaTop: safeTop,
            notchWidth: notchWidth,
            notchHeight: notchHeight,
            notchMidX: notchMidX
        )
    }

    private func islandScreenRect(expanded: Bool) -> CGRect {
        guard let panel else { return .zero }
        let local = session.metrics.hitRect(
            expanded: expanded,
            height: expanded ? session.tab.islandHeight : nil
        )
        return local.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
    }

    private func handlePointerMove() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastMoveAt >= 0.05 else { return }
        lastMoveAt = now

        let loc = NSEvent.mouseLocation
        let inside = islandScreenRect(expanded: session.isExpanded).contains(loc)
        guard inside != pointerInside else { return }
        pointerInside = inside
        handleHover(inside)
    }

    private func handleHover(_ hovering: Bool) {
        if hovering, !suppressHoverUntilExit {
            IslandHaptic.enter()
        }
        guard AppState.shared.settings.islandHoverExpand else {
            if !hovering { suppressHoverUntilExit = false }
            return
        }
        hoverWorkItem?.cancel()
        collapseWorkItem?.cancel()
        if hovering {
            if suppressHoverUntilExit { return }
            let delay = AppState.shared.settings.islandHoverDelay
            let item = DispatchWorkItem { [weak self] in
                self?.setExpanded(true)
            }
            hoverWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        } else {
            suppressHoverUntilExit = false
            guard !session.isLocked else { return }
            let item = DispatchWorkItem { [weak self] in
                self?.setExpanded(false)
            }
            collapseWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32, execute: item)
        }
    }

    private func toggleLock() {
        session.isLocked.toggle()
        if session.isLocked {
            cancelPending()
            setExpanded(true)
        } else if !pointerInside {
            collapse()
        }
    }

    private func dismissThen(_ work: @escaping () -> Void) {
        suppressHoverUntilExit = true
        collapse()
        work()
    }

    private func handleTap() {
        hoverWorkItem?.cancel()
        collapseWorkItem?.cancel()
        suppressHoverUntilExit = true
        setExpanded(!session.isExpanded)
    }

    private func setExpanded(_ expanded: Bool) {
        if !expanded, session.isLocked { return }
        guard session.isExpanded != expanded else {
            applyMousePolicy()
            return
        }
        if expanded {
            IslandHaptic.expand()
        }
        session.isExpanded = expanded
        applyMousePolicy()
    }

    private func applyMousePolicy() {
        panel?.ignoresMouseEvents = !session.isExpanded
    }

    private func cancelPending() {
        hoverWorkItem?.cancel()
        collapseWorkItem?.cancel()
        hoverWorkItem = nil
        collapseWorkItem = nil
    }

    private func startWatching() {
        stopWatching()
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
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }

        let moveHandler: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor in self?.handlePointerMove() }
        }
        globalMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: moveHandler)
        localMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { event in
            moveHandler(event)
            return event
        }

        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.session.isExpanded else { return }
                if !self.islandScreenRect(expanded: true).contains(NSEvent.mouseLocation) {
                    self.collapse()
                }
            }
        }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in self?.collapse() }
            }
        }
        rightClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.islandScreenRect(expanded: self.session.isExpanded).contains(NSEvent.mouseLocation) {
                    self.showContextMenu()
                }
            }
        }
    }

    private func stopWatching() {
        appearanceTimer?.invalidate()
        appearanceTimer = nil
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
            self.spaceObserver = nil
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        if let globalMoveMonitor {
            NSEvent.removeMonitor(globalMoveMonitor)
            self.globalMoveMonitor = nil
        }
        if let localMoveMonitor {
            NSEvent.removeMonitor(localMoveMonitor)
            self.localMoveMonitor = nil
        }
        if let mouseDownMonitor {
            NSEvent.removeMonitor(mouseDownMonitor)
            self.mouseDownMonitor = nil
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let rightClickMonitor {
            NSEvent.removeMonitor(rightClickMonitor)
            self.rightClickMonitor = nil
        }
    }

    private func updateAppearance() {
        guard let panel, AppState.shared.showDynamicIsland else { return }
        if AppState.shared.settings.hideIslandInFullscreen, isFrontAppFullscreen() {
            if panel.isVisible { panel.orderOut(nil) }
            collapse()
            return
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
            reposition()
            applyMousePolicy()
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
            guard let screen = preferredScreen() ?? NSScreen.main else { continue }
            if w >= screen.frame.width - 2 && h >= screen.frame.height - 2 {
                return true
            }
        }
        return false
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettingsAction), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let hideItem = NSMenuItem(title: "隐藏灵动岛", action: #selector(hideIslandAction), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func openSettingsAction() {
        collapse()
        onOpenSettings?()
    }

    @objc private func hideIslandAction() {
        onAction?(.toggleDynamicIsland)
    }
}
