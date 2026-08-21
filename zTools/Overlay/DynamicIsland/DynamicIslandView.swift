import AppKit
import SwiftUI

enum IslandTab: Hashable {
    case tools
    case apps
    case stats

    var islandHeight: CGFloat {
        switch self {
        case .tools: IslandMetrics.toolsHeight
        case .apps, .stats: IslandMetrics.contentHeight
        }
    }
}

@MainActor
final class DynamicIslandSession: ObservableObject {
    @Published var isExpanded = false
    @Published var isLocked = false
    @Published var tab: IslandTab = .tools
    @Published var metrics = IslandMetrics.make(
        screenWidth: 1728,
        visibleTopInset: 33,
        safeAreaTop: 32,
        notchWidth: 185,
        notchHeight: 32
    )
}

@MainActor
final class InstalledAppStore: ObservableObject {
    struct Item: Identifiable {
        let id: URL
        let name: String
        let icon: NSImage
    }

    struct AppRef: Sendable {
        let url: URL
        let name: String
    }

    @Published var apps: [Item] = []
    @Published var isLoading = false
    private var didLoad = false

    func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        isLoading = true
        Task { [weak self] in
            let refs = await Task.detached(priority: .userInitiated) {
                InstalledAppStore.scanRefs()
            }.value
            guard let self else { return }
            apps = refs.map { ref in
                let icon = NSWorkspace.shared.icon(forFile: ref.url.path)
                icon.size = NSSize(width: 64, height: 64)
                return Item(id: ref.url, name: ref.name, icon: icon)
            }
            isLoading = false
        }
    }

    nonisolated static func scanRefs() -> [AppRef] {
        let fm = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications", isDirectory: true),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]
        var seen = Set<String>()
        var result: [AppRef] = []

        func consider(_ url: URL) {
            guard url.pathExtension == "app" else { return }
            let key = url.deletingPathExtension().lastPathComponent.lowercased()
            guard !key.hasPrefix(".") else { return }
            guard seen.insert(key).inserted else { return }
            result.append(AppRef(url: url, name: fm.displayName(atPath: url.path)))
        }

        for root in roots {
            guard let items = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in items {
                if url.pathExtension == "app" {
                    consider(url)
                } else {
                    guard let nested = try? fm.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    ) else { continue }
                    nested.filter { $0.pathExtension == "app" }.forEach(consider)
                }
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct IslandSurface: Shape {
    var progress: CGFloat
    var collapsed: CGSize
    var expanded: CGSize

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, expanded.height) }
        set {
            progress = newValue.first
            expanded.height = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let t = progress
        let w = max(1, collapsed.width + (expanded.width - collapsed.width) * t)
        let heightT = t > 1 ? 1 + (t - 1) * 0.35 : t
        let h = max(1, min(
            collapsed.height + (expanded.height - collapsed.height) * heightT,
            rect.height
        ))
        let box = CGRect(x: (rect.width - w) / 2, y: 0, width: w, height: h)
        let cornerT = min(max(t, 0), 1.08)
        let tr = 8 + (IslandMetrics.maxTopRadius - 8) * cornerT
        let pillR = min(collapsed.height, collapsed.width) / 2
        let br = min(pillR + (24 - pillR) * min(cornerT, 1), h / 2, w / 4)
        return Self.fusedPath(in: box, top: min(tr, h / 2, w / 6), bottom: br)
    }

    private static func fusedPath(in rect: CGRect, top: CGFloat, bottom: CGFloat) -> Path {
        let tr = max(0, top)
        let br = max(0, bottom)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX - tr, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX + tr, y: rect.minY))

        if tr > 0.5 {
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + tr),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - br, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + br, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - br),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tr))

        if tr > 0.5 {
            path.addQuadCurve(
                to: CGPoint(x: rect.minX - tr, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.minY)
            )
        }

        path.closeSubpath()
        return path
    }
}

struct DynamicIslandView: View {
    @ObservedObject var session: DynamicIslandSession
    let onTap: () -> Void
    let onSelect: (ToolAction) -> Void
    let onOpenSettings: () -> Void
    let onLaunchApp: (URL) -> Void
    let onToggleLock: () -> Void

    @ObservedObject private var settings = AppState.shared.settings
    @StateObject private var apps = InstalledAppStore()
    @StateObject private var stats = IslandStatsStore()
    @State private var progress: CGFloat = 0
    @Namespace private var tabNS

    private var metrics: IslandMetrics { session.metrics }
    private var tabHeight: CGFloat { session.tab.islandHeight }
    private var expandedSize: CGSize { metrics.islandSize(expanded: true, height: tabHeight) }
    private var collapsedSize: CGSize { metrics.islandSize(expanded: false) }

    private var surface: IslandSurface {
        IslandSurface(progress: progress, collapsed: collapsedSize, expanded: expandedSize)
    }

    private var contentOpacity: Double {
        Double(min(1, max(0, (progress - 0.14) / 0.4)))
    }

    private var collapsedOpacity: Double {
        Double(min(1, max(0, 1 - progress / 0.2)))
    }

    private var contentScale: CGFloat {
        0.96 + 0.04 * min(1, max(0, progress))
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private let toolColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    private let appColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        Color.clear
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    collapsedHeader
                        .frame(width: collapsedSize.width, height: collapsedSize.height)
                        .opacity(collapsedOpacity)
                        .allowsHitTesting(false)

                    expandedPanel
                        .frame(width: expandedSize.width, height: expandedSize.height, alignment: .top)
                        .scaleEffect(contentScale, anchor: .top)
                        .opacity(contentOpacity)
                        .allowsHitTesting(session.isExpanded)
                }
                .frame(
                    width: expandedSize.width + IslandMetrics.maxTopRadius * 2 + 48,
                    height: expandedSize.height + 20,
                    alignment: .top
                )
                .background(surface.fill(Color.black))
                .clipShape(surface)
                .contentShape(surface)
                .offset(x: metrics.notchMidX - metrics.screenWidth / 2)
            }
            .ignoresSafeArea(edges: .all)
            .onAppear {
                progress = session.isExpanded ? 1 : 0
                if session.isExpanded { apps.loadIfNeeded() }
                syncStatsPolling()
            }
            .onChange(of: session.isExpanded) { _, open in
                withAnimation(open ? expandAnimation : collapseAnimation) {
                    progress = open ? 1 : 0
                }
                if open { apps.loadIfNeeded() }
                syncStatsPolling()
            }
            .onChange(of: session.tab) { _, _ in
                syncStatsPolling()
            }
            .onChange(of: settings.islandLeftWing) { _, _ in
                syncStatsPolling()
            }
            .onChange(of: settings.islandRightWing) { _, _ in
                syncStatsPolling()
            }
            .onDisappear {
                stats.stop()
            }
    }

    private var collapsedHeader: some View {
        HStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                IslandWingView(kind: settings.islandLeftWing, date: context.date, stats: stats)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 8)
            }

            Color.clear
                .frame(width: metrics.hasNotch ? metrics.notchWidth : 8)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                IslandWingView(kind: settings.islandRightWing, date: context.date, stats: stats)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 8)
            }
        }
    }

    private var expandedPanel: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: metrics.hasNotch ? metrics.notchHeight : 10)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)

            toolbar
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 8)

            Group {
                switch session.tab {
                case .tools: toolsGrid
                case .apps: appsGrid
                case .stats: statsPanel
                }
            }
            .id(session.tab)
            .transition(tabContentTransition)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                tabChip("工具", tab: .tools)
                tabChip("应用", tab: .apps)
                tabChip("状态", tab: .stats)
            }
            .padding(3)
            .background(Capsule(style: .continuous).fill(Color.white.opacity(0.10)))

            Spacer(minLength: 8)

            Button(action: onToggleLock) {
                Image(systemName: session.isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(session.isLocked ? Color.white : Color.white.opacity(0.55))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(session.isLocked ? "解除锁定" : "锁定展开")

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("设置")
        }
    }

    private func tabChip(_ title: String, tab: IslandTab) -> some View {
        let selected = session.tab == tab
        return Button {
            withAnimation(tabAnimation) {
                session.tab = tab
            }
            if tab == .apps { apps.loadIfNeeded() }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.55))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    if selected {
                        Capsule(style: .continuous)
                            .fill(ZTheme.accent)
                            .matchedGeometryEffect(id: "islandTabPill", in: tabNS)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var toolsGrid: some View {
        LazyVGrid(columns: toolColumns, spacing: 8) {
            ForEach(ToolAction.launcherItems) { action in
                toolButton(action)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    private var appsGrid: some View {
        Group {
            if apps.isLoading && apps.apps.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if apps.apps.isEmpty {
                Text("未找到应用")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: appColumns, spacing: 12) {
                        ForEach(apps.apps) { item in
                            appButton(item)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.never)
            }
        }
    }

    private var statsPanel: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    IslandGauge(
                        title: "CPU",
                        value: stats.cpu,
                        color: Color(red: 0.62, green: 0.48, blue: 1.0)
                    )
                    IslandGauge(
                        title: "内存",
                        value: stats.memoryRatio,
                        detail: "\(IslandStatsStore.formatBytes(stats.memoryUsed)) / \(IslandStatsStore.formatBytes(stats.memoryTotal))",
                        color: Color(red: 0.35, green: 0.78, blue: 0.98)
                    )
                    IslandGauge(
                        title: "电池",
                        value: stats.batteryRatio,
                        detail: batteryDetail,
                        color: batteryColor
                    )
                }

                HStack(spacing: 8) {
                    statsChip(icon: "arrow.down.circle.fill", title: "下载", value: IslandStatsStore.formatRate(stats.netIn))
                    statsChip(icon: "arrow.up.circle.fill", title: "上传", value: IslandStatsStore.formatRate(stats.netOut))
                }

                statsRow(icon: "headphones", title: accessoryTitle, value: accessoryValue)
                statsRow(
                    icon: "internaldrive",
                    title: "磁盘",
                    value: stats.diskTotal == 0
                        ? "—"
                        : "\(IslandStatsStore.formatBytes(stats.diskUsed)) / \(IslandStatsStore.formatBytes(stats.diskTotal))"
                )
                statsRow(icon: "clock", title: "运行时间", value: IslandStatsStore.formatUptime(stats.uptime))
                statsRow(icon: "thermometer.medium", title: "温度状态", value: stats.thermalLabel)
                statsRow(icon: "chart.bar", title: "负载", value: stats.loadAverage)
                statsRow(icon: "cpu", title: "处理器", value: "\(stats.coreCount) 核")
                statsRow(icon: "display", title: "显示器", value: displayInfo)
                statsRow(icon: "network", title: "本机 IP", value: stats.localIP)
                statsRow(icon: "laptopcomputer", title: "设备", value: "\(stats.deviceModel) · \(stats.osVersion)")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.never)
    }

    private var batteryDetail: String {
        if stats.batteryPercent == nil { return "不可用" }
        if stats.batteryTime != "—" { return stats.batteryTime }
        return stats.batteryCharging ? "充电中" : "未充电"
    }

    private var displayInfo: String {
        guard let screen = NSScreen.main else { return "—" }
        let w = Int(screen.frame.width)
        let h = Int(screen.frame.height)
        let scale = screen.backingScaleFactor
        return "\(w)×\(h) @\(scale == 1 ? "1x" : String(format: "%.0fx", scale))"
    }

    private var batteryColor: Color {
        let p = stats.batteryPercent ?? 100
        if stats.batteryCharging { return Color(red: 0.45, green: 0.88, blue: 0.55) }
        if p <= 20 { return Color(red: 1.0, green: 0.42, blue: 0.38) }
        return Color(red: 0.45, green: 0.88, blue: 0.55)
    }

    private var accessoryTitle: String {
        stats.accessories.first?.name ?? "耳机"
    }

    private var accessoryValue: String {
        guard let item = stats.accessories.first else { return "未连接" }
        if let p = item.percent { return "\(p)%" }
        return "已连接"
    }

    private func statsChip(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
    }

    private func statsRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 18)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
    }

    private func syncStatsPolling() {
        let liveWings = settings.islandLeftWing.needsLiveStats || settings.islandRightWing.needsLiveStats
        let active = (session.isExpanded && session.tab == .stats) || liveWings
        DispatchQueue.main.async {
            if active {
                stats.start()
            } else {
                stats.stop()
            }
        }
    }

    private func appButton(_ item: InstalledAppStore.Item) -> some View {
        Button {
            onLaunchApp(item.id)
        } label: {
            VStack(spacing: 5) {
                Image(nsImage: item.icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                Text(item.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(item.name)
    }

    private func toolButton(_ action: ToolAction) -> some View {
        Button {
            onSelect(action)
        } label: {
            VStack(spacing: 5) {
                ZIconTile(systemImage: action.systemImage, size: 40)
                    .colorScheme(.dark)
                Text(action.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                if let shortcut = shortcutLabel(for: action) {
                    Text(shortcut)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(helpText(for: action))
    }

    private var expandAnimation: Animation {
        if reduceMotion { return .easeOut(duration: 0.12) }
        return ZTheme.springIsland
    }

    private var collapseAnimation: Animation {
        if reduceMotion { return .easeOut(duration: 0.1) }
        return .spring(duration: 0.28, bounce: 0.02)
    }

    private var tabAnimation: Animation {
        if reduceMotion { return .easeOut(duration: 0.12) }
        return .spring(duration: 0.32, bounce: 0.08)
    }

    private var tabContentTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.97)).combined(with: .offset(y: 8)),
            removal: .opacity.combined(with: .scale(scale: 1.02))
        )
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

private struct IslandGauge: View {
    let title: String
    let value: Double
    var detail: String? = nil
    var color: Color

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: min(max(value, 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((min(max(value, 0), 1) * 100).rounded()))%")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .frame(width: 72, height: 72)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Text(detail ?? " ")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}
