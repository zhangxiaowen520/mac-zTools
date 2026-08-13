import AppKit
import ScreenCaptureKit
import SwiftUI

enum CaptureMode {
    case region
    case fullscreen
    case delayFullscreen
    case windowUnderCursor
    case lastRegion
    case presetSize
}

enum CaptureFinishAction {
    case copy, edit, pin, save, ocr, cancelled
}

struct CaptureResult {
    let image: NSImage
    let action: CaptureFinishAction
    let region: CGRect?
}

@MainActor
final class ScreenshotService {
    private var activeOverlay: RegionSelectionOverlay?
    private var countdownPanel: NSPanel?

    func capture(_ mode: CaptureMode) async throws -> CaptureResult? {
        switch mode {
        case .region:
            return try await captureInteractive()
        case .fullscreen:
            guard let screen = NSScreen.main else { throw ScreenshotError.noDisplay }
            let img = try await captureImage(rectInScreenCocoa: screen.frame)
            let final = ScreenshotEffects.apply(to: img)
            ScreenshotEffects.playShutterIfNeeded()
            return CaptureResult(image: final, action: ScreenshotSettings.shared.defaultAction.toFinish, region: screen.frame)
        case .delayFullscreen:
            let sec = max(1, ScreenshotSettings.shared.delaySeconds)
            let cancelled = await showCountdown(seconds: sec)
            if cancelled { return nil }
            guard let screen = NSScreen.main else { throw ScreenshotError.noDisplay }
            let img = try await captureImage(rectInScreenCocoa: screen.frame)
            let final = ScreenshotEffects.apply(to: img)
            ScreenshotEffects.playShutterIfNeeded()
            return CaptureResult(image: final, action: ScreenshotSettings.shared.defaultAction.toFinish, region: screen.frame)
        case .windowUnderCursor:
            guard let win = WindowCaptureHelper.windowUnderMouse() else {
                throw ScreenshotError.noWindow
            }
            let img = try await captureImage(rectInScreenCocoa: win.frame)
            let final = ScreenshotEffects.apply(to: img)
            ScreenshotEffects.playShutterIfNeeded()
            ScreenshotSettings.shared.lastRegion = win.frame
            return CaptureResult(image: final, action: ScreenshotSettings.shared.defaultAction.toFinish, region: win.frame)
        case .lastRegion:
            guard let rect = ScreenshotSettings.shared.lastRegion else {
                throw ScreenshotError.noLastRegion
            }
            let img = try await captureImage(rectInScreenCocoa: rect)
            let final = ScreenshotEffects.apply(to: img)
            ScreenshotEffects.playShutterIfNeeded()
            return CaptureResult(image: final, action: ScreenshotSettings.shared.defaultAction.toFinish, region: rect)
        case .presetSize:
            let w = CGFloat(max(50, ScreenshotSettings.shared.presetWidth))
            let h = CGFloat(max(50, ScreenshotSettings.shared.presetHeight))
            let mouse = NSEvent.mouseLocation
            var rect = CGRect(x: mouse.x - w / 2, y: mouse.y - h / 2, width: w, height: h)
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
                rect.origin.x = min(max(rect.origin.x, screen.frame.minX), screen.frame.maxX - w)
                rect.origin.y = min(max(rect.origin.y, screen.frame.minY), screen.frame.maxY - h)
            }
            let img = try await captureImage(rectInScreenCocoa: rect)
            let final = ScreenshotEffects.apply(to: img)
            ScreenshotEffects.playShutterIfNeeded()
            ScreenshotSettings.shared.lastRegion = rect
            return CaptureResult(image: final, action: ScreenshotSettings.shared.defaultAction.toFinish, region: rect)
        }
    }

    /// 兼容旧 API
    func captureRegion() async throws -> NSImage? {
        try await captureInteractive()?.image
    }

    private func captureInteractive() async throws -> CaptureResult? {
        try await withCheckedThrowingContinuation { continuation in
            let overlay = RegionSelectionOverlay()
            self.activeOverlay = overlay
            overlay.begin { [weak self] result in
                self?.activeOverlay = nil
                switch result {
                case .cancelled:
                    continuation.resume(returning: nil)
                case .failed(let error):
                    continuation.resume(throwing: error)
                case .captured(let image, let action, let region):
                    ScreenshotSettings.shared.lastRegion = region
                    ScreenshotEffects.playShutterIfNeeded()
                    let final = ScreenshotEffects.apply(to: image)
                    continuation.resume(returning: CaptureResult(image: final, action: action, region: region))
                }
            }
        }
    }

    func captureImage(rectInScreenCocoa: CGRect) async throws -> NSImage {
        let rect = rectInScreenCocoa.standardized
        guard rect.width > 1, rect.height > 1 else { throw ScreenshotError.failed }

        var lastError: Error?
        do {
            return try await captureWithScreenCaptureKit(rectInScreenCocoa: rect)
        } catch {
            lastError = error
            NSLog("SCK failed: \(error.localizedDescription)")
        }

        if let image = captureWithScreencaptureCLI(rectInScreenCocoa: rect) {
            return image
        }

        let can = await PermissionHelper.canAccessScreenContent()
        if !can { throw ScreenshotError.noPermission }
        throw lastError ?? ScreenshotError.failed
    }

    private func captureWithScreenCaptureKit(rectInScreenCocoa: CGRect) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        let scaleHint = NSScreen.screens.first(where: {
            $0.frame.intersects(rectInScreenCocoa)
        })?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2

        // 像素对齐，减少亚像素采样模糊
        let alignedCocoa = RetinaImage.alignRect(rectInScreenCocoa.standardized, scale: scaleHint)
        let cgRect = ScreenCoordinate.convertCocoaRectToCG(alignedCocoa)

        guard let display = content.displays.first(where: {
            CGDisplayBounds($0.displayID).intersects(cgRect)
        }) ?? content.displays.first else {
            throw ScreenshotError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        let displayBounds = CGDisplayBounds(display.displayID)

        var local = CGRect(
            x: cgRect.minX - displayBounds.minX,
            y: cgRect.minY - displayBounds.minY,
            width: max(1, cgRect.width),
            height: max(1, cgRect.height)
        )
        local = local.intersection(CGRect(origin: .zero, size: displayBounds.size))
        guard local.width > 1, local.height > 1 else { throw ScreenshotError.failed }

        let scale = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID
        })?.backingScaleFactor ?? scaleHint

        // 按物理像素请求，避免中间缩放
        let pixelW = max(1, Int((local.width * scale).rounded(.toNearestOrAwayFromZero)))
        let pixelH = max(1, Int((local.height * scale).rounded(.toNearestOrAwayFromZero)))
        config.width = pixelW
        config.height = pixelH
        config.sourceRect = local
        config.scalesToFit = false
        config.showsCursor = ScreenshotSettings.shared.captureCursor
        config.captureResolution = .best

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        // point size = 逻辑尺寸；像素由 cgImage 完整保留
        let pointSize = NSSize(width: local.width, height: local.height)
        return RetinaImage.from(cgImage: cgImage, pointSize: pointSize)
    }

    private func captureWithScreencaptureCLI(rectInScreenCocoa: CGRect) -> NSImage? {
        let cg = ScreenCoordinate.convertCocoaRectToCG(rectInScreenCocoa)
        let x = Int(cg.minX.rounded())
        let y = Int(cg.minY.rounded())
        let w = Int(max(1, cg.width).rounded())
        let h = Int(max(1, cg.height).rounded())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ztools-cap-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        var args = ["-x", "-t", "png", "-R", "\(x),\(y),\(w),\(h)"]
        if ScreenshotSettings.shared.captureCursor { args.insert("-C", at: 1) }
        args.append(url.path)
        process.arguments = args
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0, let image = NSImage(contentsOf: url) else { return nil }
            return image
        } catch {
            return nil
        }
    }

    private func showCountdown(seconds: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            var remaining = seconds
            var cancelled = false
            let label = NSTextField(labelWithString: "\(remaining)")
            label.font = .systemFont(ofSize: 72, weight: .bold)
            label.textColor = .white
            label.alignment = .center
            label.frame = NSRect(x: 0, y: 0, width: 160, height: 160)

            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 160, height: 160),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = NSColor.black.withAlphaComponent(0.45)
            panel.level = .statusBar
            panel.contentView = label
            panel.hasShadow = true
            if let screen = NSScreen.main {
                let v = screen.visibleFrame
                panel.setFrameOrigin(CGPoint(x: v.midX - 80, y: v.midY - 80))
            }
            panel.orderFrontRegardless()
            self.countdownPanel = panel

            let mon = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 {
                    cancelled = true
                    return nil
                }
                return event
            }

            @MainActor
            func tick() {
                if cancelled {
                    if let mon { NSEvent.removeMonitor(mon) }
                    panel.orderOut(nil)
                    self.countdownPanel = nil
                    continuation.resume(returning: true)
                    return
                }
                if remaining <= 0 {
                    if let mon { NSEvent.removeMonitor(mon) }
                    panel.orderOut(nil)
                    self.countdownPanel = nil
                    continuation.resume(returning: false)
                    return
                }
                label.stringValue = "\(remaining)"
                remaining -= 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { tick() }
            }
            tick()
        }
    }
}

extension CaptureAfterAction {
    var toFinish: CaptureFinishAction {
        switch self {
        case .copy: .copy
        case .edit: .edit
        case .pin: .pin
        case .save: .save
        case .ocr: .ocr
        }
    }
}

enum ScreenshotError: LocalizedError {
    case noPermission
    case noDisplay
    case failed
    case noWindow
    case noLastRegion

    var errorDescription: String? {
        switch self {
        case .noPermission:
            "需要屏幕录制权限（若已开启请完全退出 zTools 后重试）"
        case .noDisplay: "未找到可用显示器"
        case .failed: "截图失败"
        case .noWindow: "光标下没有可截取的窗口"
        case .noLastRegion: "还没有上次截图区域，请先区域截图一次"
        }
    }
}

// MARK: - Selection Overlay

@MainActor
final class RegionSelectionOverlay {
    enum Result {
        case cancelled
        case failed(Error)
        case captured(NSImage, CaptureFinishAction, CGRect)
    }

    private var windows: [NSWindow] = []
    private var completion: ((Result) -> Void)?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var actionPanel: NSPanel?
    private let captureHelper = ScreenshotServiceCapture()

    func begin(completion: @escaping (Result) -> Void) {
        self.completion = completion
        let showCross = ScreenshotSettings.shared.showCrosshair

        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = SelectionView(
                screenFrame: screen.frame,
                showCrosshair: showCross,
                onComplete: { [weak self] rect, action in
                    self?.finish(with: rect, preferredAction: action)
                },
                onCancel: { [weak self] in self?.cancel() }
            )
            window.contentView = view
            window.setFrame(screen.frame, display: true)
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        installKeyMonitor()
    }

    private func installKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Esc
            if event.keyCode == 53 {
                self.cancel()
                return nil
            }
            // Return while action bar visible → default action
            if event.keyCode == 36, self.actionPanel != nil {
                self.actionPanelDefault()
                return nil
            }
            return event
        }
    }

    private func finish(with globalRect: CGRect?, preferredAction: CaptureFinishAction?) {
        hideSelectionWindows()
        guard let globalRect, globalRect.width > 2, globalRect.height > 2 else {
            finishCancel()
            return
        }

        if let preferredAction {
            capture(rect: globalRect, action: preferredAction)
            return
        }
        presentActionBar(for: globalRect)
    }

    private var pendingActionRect: CGRect?

    private func actionPanelDefault() {
        guard actionPanel != nil, let rect = pendingActionRect else { return }
        let action = ScreenshotSettings.shared.defaultAction.toFinish
        capture(rect: rect, action: action)
    }

    private func presentActionBar(for rect: CGRect) {
        pendingActionRect = rect
        dismissActionBarUI()
        let defaultAction = ScreenshotSettings.shared.defaultAction.toFinish

        // 面板本身不要阴影/描边，否则会露出矩形线框；阴影只画在胶囊上
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovableByWindowBackground = false

        let bar = CaptureActionBarView(
            onCopy: { [weak self] in self?.capture(rect: rect, action: .copy) },
            onEdit: { [weak self] in self?.capture(rect: rect, action: .edit) },
            onPin: { [weak self] in self?.capture(rect: rect, action: .pin) },
            onSave: { [weak self] in self?.capture(rect: rect, action: .save) },
            onOCR: { [weak self] in self?.capture(rect: rect, action: .ocr) },
            onCancel: { [weak self] in self?.finishCancel() },
            defaultAction: defaultAction
        )

        let hosting = NSHostingView(rootView: bar)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        // 透明宿主，避免矩形底
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting
        let size = hosting.fittingSize
        panel.setContentSize(size)

        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            var origin = CGPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 14)
            if origin.y < visible.minY {
                origin.y = min(rect.maxY + 14, visible.maxY - size.height - 8)
            }
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            panel.setFrameOrigin(origin)
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        actionPanel = panel
        installKeyMonitor()

        // 延迟安装，避免松手的 mouseUp 立刻取消
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.actionPanel != nil else { return }
            self.clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self, let actionPanel = self.actionPanel else { return }
                let loc = NSEvent.mouseLocation
                if !actionPanel.frame.contains(loc) {
                    Task { @MainActor in self.finishCancel() }
                }
            }
        }
    }

    private func capture(rect: CGRect, action: CaptureFinishAction) {
        dismissActionBarUI()
        removeMonitors()
        pendingActionRect = nil
        let completion = self.completion
        self.completion = nil

        // 稍等一帧，确保 overlay 已从屏幕消失再截
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000)
            do {
                let image = try await captureHelper.capture(rectInScreenCocoa: rect.standardized)
                completion?(.captured(image, action, rect.standardized))
            } catch {
                completion?(.failed(error))
            }
        }
    }

    private func finishCancel() {
        dismissActionBarUI()
        hideSelectionWindows()
        removeMonitors()
        pendingActionRect = nil
        let completion = self.completion
        self.completion = nil
        completion?(.cancelled)
    }

    private func cancel() {
        finishCancel()
    }

    private func dismissActionBarUI() {
        actionPanel?.orderOut(nil)
        actionPanel = nil
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    private func hideSelectionWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func removeMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }
}

@MainActor
final class ScreenshotServiceCapture {
    func capture(rectInScreenCocoa: CGRect) async throws -> NSImage {
        try await ScreenshotService().captureImage(rectInScreenCocoa: rectInScreenCocoa)
    }
}

// MARK: - Action bar

struct CaptureActionBarView: View {
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onPin: () -> Void
    let onSave: () -> Void
    let onOCR: () -> Void
    let onCancel: () -> Void
    let defaultAction: CaptureFinishAction

    var body: some View {
        HStack(spacing: 6) {
            actionButton(title: "复制", icon: "doc.on.doc", isDefault: defaultAction == .copy, action: onCopy)
            actionButton(title: "编辑", icon: "pencil", isDefault: defaultAction == .edit, action: onEdit)
            actionButton(title: "钉图", icon: "pin.fill", isDefault: defaultAction == .pin, action: onPin)
            actionButton(title: "保存", icon: "square.and.arrow.down", isDefault: defaultAction == .save, action: onSave)
            actionButton(title: "OCR", icon: "text.viewfinder", isDefault: defaultAction == .ocr, action: onOCR)

            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 1, height: 18)
                .padding(.horizontal, 2)

            Button(action: onCancel) {
                Text("取消")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // 实色半透明底，避免 material + 窗口矩形阴影叠出线框
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.72))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        // 给阴影留白，但宿主窗口无矩形阴影，不会出现方框
        .padding(12)
        .fixedSize()
    }

    private func actionButton(title: String, icon: String, isDefault: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(isDefault ? Color.black.opacity(0.88) : Color.white.opacity(0.92))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(isDefault ? Color.white : Color.white.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

// MARK: - Selection View

final class SelectionView: NSView {
    private let screenFrame: CGRect
    private let showCrosshair: Bool
    private let onComplete: (CGRect?, CaptureFinishAction?) -> Void
    private let onCancel: () -> Void

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var mousePoint: CGPoint = .zero
    private var hoverWindow: CGRect?
    private var tracking: NSTrackingArea?
    private var didDrag = false
    private var hoverQueryWork: DispatchWorkItem?

    init(
        screenFrame: CGRect,
        showCrosshair: Bool,
        onComplete: @escaping (CGRect?, CaptureFinishAction?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.screenFrame = screenFrame
        self.showCrosshair = showCrosshair
        self.onComplete = onComplete
        self.onCancel = onCancel
        super.init(frame: NSRect(origin: .zero, size: screenFrame.size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        updateTracking()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateTracking()
    }

    private func updateTracking() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        mousePoint = convert(event.locationInWindow, from: nil)
        if startPoint == nil {
            scheduleHoverQuery()
        }
        needsDisplay = true
    }

    /// 悬停窗口查询走尾端去抖，避免逐帧调用 CGWindowListCopyWindowInfo 造成掉帧。
    private func scheduleHoverQuery() {
        hoverQueryWork?.cancel()
        let global = CGPoint(x: screenFrame.minX + mousePoint.x, y: screenFrame.minY + mousePoint.y)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hoverQueryWork = nil
            if let win = WindowCaptureHelper.windowAtPoint(global) {
                self.hoverWindow = CGRect(
                    x: win.frame.minX - self.screenFrame.minX,
                    y: win.frame.minY - self.screenFrame.minY,
                    width: win.frame.width,
                    height: win.frame.height
                )
            } else {
                self.hoverWindow = nil
            }
            self.needsDisplay = true
        }
        hoverQueryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Dim
        let dim = NSColor.black.withAlphaComponent(0.38)
        if let startPoint, let currentPoint, didDrag {
            let rect = CGRect(
                x: min(startPoint.x, currentPoint.x),
                y: min(startPoint.y, currentPoint.y),
                width: abs(startPoint.x - currentPoint.x),
                height: abs(startPoint.y - currentPoint.y)
            )
            let path = NSBezierPath(rect: bounds)
            path.append(NSBezierPath(rect: rect).reversed)
            path.windingRule = .evenOdd
            dim.setFill()
            path.fill()

            NSColor.white.withAlphaComponent(0.95).setStroke()
            let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1.5
            border.stroke()

            drawSizeLabel(for: rect)
        } else {
            dim.setFill()
            bounds.fill()

            // Hover window highlight
            if let hover = hoverWindow {
                NSColor.clear.setFill()
                let path = NSBezierPath(rect: bounds)
                path.append(NSBezierPath(rect: hover).reversed)
                path.windingRule = .evenOdd
                dim.setFill()
                path.fill()
                NSColor.systemBlue.withAlphaComponent(0.9).setStroke()
                let b = NSBezierPath(rect: hover.insetBy(dx: 1, dy: 1))
                b.lineWidth = 2
                b.stroke()
                drawHint("单击截取窗口 · 拖拽选择区域 · Esc 取消", at: CGPoint(x: hover.midX, y: hover.minY - 28))
            } else {
                drawHint("拖拽选择区域 · 悬停高亮窗口 · Esc 取消", at: CGPoint(x: bounds.midX, y: bounds.midY))
            }
        }

        if showCrosshair, startPoint == nil {
            NSColor.white.withAlphaComponent(0.35).setStroke()
            let v = NSBezierPath()
            v.move(to: CGPoint(x: mousePoint.x, y: 0))
            v.line(to: CGPoint(x: mousePoint.x, y: bounds.height))
            v.lineWidth = 1
            v.stroke()
            let h = NSBezierPath()
            h.move(to: CGPoint(x: 0, y: mousePoint.y))
            h.line(to: CGPoint(x: bounds.width, y: mousePoint.y))
            h.lineWidth = 1
            h.stroke()
        }
    }

    private func drawSizeLabel(for rect: CGRect) {
        let label = "\(Int(rect.width)) × \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = label.size(withAttributes: attrs)
        var labelRect = CGRect(x: rect.midX - size.width / 2 - 6, y: rect.minY - 28, width: size.width + 12, height: 20)
        if labelRect.minY < 4 { labelRect.origin.y = rect.maxY + 8 }
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 6, yRadius: 6).fill()
        label.draw(at: CGPoint(x: labelRect.minX + 6, y: labelRect.minY + 3), withAttributes: attrs)
    }

    private func drawHint(_ text: String, at center: CGPoint) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attrs)
        let rect = CGRect(x: center.x - size.width / 2 - 12, y: center.y - 14, width: size.width + 24, height: 28)
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        text.draw(at: CGPoint(x: rect.minX + 12, y: rect.minY + 6), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        hoverQueryWork?.cancel()
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        didDrag = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        if let s = startPoint, let c = currentPoint,
           hypot(c.x - s.x, c.y - s.y) > 4 {
            didDrag = true
            hoverWindow = nil
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        let mods = event.modifierFlags

        // Click without drag → capture hover window
        if !didDrag {
            if let hover = hoverWindow {
                let global = CGRect(
                    x: screenFrame.minX + hover.minX,
                    y: screenFrame.minY + hover.minY,
                    width: hover.width,
                    height: hover.height
                )
                let action = actionFromModifiers(mods) ?? ScreenshotSettings.shared.defaultAction.toFinish
                // 单击窗口：直接默认动作，不弹条
                onComplete(global, action)
                return
            }
            onComplete(nil, nil)
            return
        }

        guard let startPoint, let currentPoint else {
            onComplete(nil, nil)
            return
        }
        let local = CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        )
        guard local.width > 2, local.height > 2 else {
            onComplete(nil, nil)
            return
        }
        let global = CGRect(
            x: screenFrame.minX + local.minX,
            y: screenFrame.minY + local.minY,
            width: local.width,
            height: local.height
        )

        // 修饰键 → 直接动作；否则动作条（传 nil）
        if let action = actionFromModifiers(mods) {
            onComplete(global, action)
        } else if event.clickCount >= 2 {
            onComplete(global, .copy)
        } else {
            onComplete(global, nil) // show action bar
        }
    }

    private func actionFromModifiers(_ mods: NSEvent.ModifierFlags) -> CaptureFinishAction? {
        if mods.contains(.command) { return .edit }
        if mods.contains(.option) { return .save }
        if mods.contains(.shift) { return .pin }
        return nil
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel() }
        if event.keyCode == 36, let hover = hoverWindow { // Enter
            let global = CGRect(
                x: screenFrame.minX + hover.minX,
                y: screenFrame.minY + hover.minY,
                width: hover.width,
                height: hover.height
            )
            onComplete(global, ScreenshotSettings.shared.defaultAction.toFinish)
        }
    }

    override func rightMouseDown(with event: NSEvent) { onCancel() }
    override func cancelOperation(_ sender: Any?) { onCancel() }
}
