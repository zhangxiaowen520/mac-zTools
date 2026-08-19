import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case screenshot
    case ai
    case shortcuts
    case permissions
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: "通用")
        case .screenshot: String(localized: "截图")
        case .ai: String(localized: "AI 翻译")
        case .shortcuts: String(localized: "快捷键")
        case .permissions: String(localized: "权限")
        case .about: String(localized: "关于")
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .screenshot: "camera.viewfinder"
        case .ai: "globe"
        case .shortcuts: "keyboard"
        case .permissions: "lock.shield"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var ss = ScreenshotSettings.shared
    @State private var tab: SettingsTab = .general
    @State private var screenshotSegment = 0
    @State private var screenPermissionOK = false
    @State private var accessibilityOK = false
    @State private var showAPIKey = false
    @State private var repairStep = 0
    @State private var testingConnection = false
    @State private var connectionMessage: String?
    @ObservedObject private var updater = UpdateChecker.shared

    init() {
        _settings = ObservedObject(wrappedValue: AppState.shared.settings)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $tab) { item in
                Label(item.title, systemImage: item.systemImage)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            Group {
                switch tab {
                case .general: generalTab
                case .screenshot: screenshotTab
                case .ai: aiTab
                case .shortcuts: shortcutsTab
                case .permissions: permissionsTab
                case .about: aboutTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
        }
        .navigationTitle("zTools 设置")
        .frame(minWidth: 740, minHeight: 500)
        .task {
            await refreshPermissions()
        }
    }

    private var generalTab: some View {
        Form {
            Section("启动") {
                Toggle("登录时启动", isOn: $settings.launchAtLogin)
            }
            Section("悬浮球") {
                Toggle("显示悬浮球", isOn: $appState.showFloatingBall)
                Toggle("边缘磁吸", isOn: $settings.snapFloatingBall)
                Toggle("贴边时半透明", isOn: $settings.dimBallNearEdge)
                Toggle("全屏应用时自动隐藏", isOn: $settings.hideBallInFullscreen)
                HStack {
                    Text("尺寸")
                    Slider(value: $settings.floatingBallSize, in: 40...64, step: 4)
                    Text("\(Int(settings.floatingBallSize))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
                .onChange(of: settings.floatingBallSize) { _, size in
                    appState.floatingBall.updateSize(size)
                }
            }
            Section("笔记") {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Markdown 目录")
                        Text(settings.notesDirectory)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button("选择…") { pickNotesDirectory() }
                    Button("还原") {
                        settings.notesDirectory = SettingsStore.defaultNotesDirectory.path
                        appState.noteStore.setDirectory(settings.notesDirectoryURL)
                    }
                    Button("打开") {
                        NSWorkspace.shared.open(settings.notesDirectoryURL)
                    }
                }
                Text("每篇笔记是一个 .md 文件。可指向已有 Markdown 文件夹。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("剪贴板") {
                Stepper(value: $settings.clipboardLimit, in: 20...300, step: 10) {
                    Text("历史条数：\(settings.clipboardLimit)")
                }
                .onChange(of: settings.clipboardLimit) { _, limit in
                    appState.clipboardStore.updateLimit(limit)
                }
                Toggle("暂停记录", isOn: $appState.isClipboardPaused)
                Button("清空历史（保留置顶）") {
                    appState.clipboardStore.clear(keepPinned: true)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var screenshotTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $screenshotSegment) {
                Text("模式与快捷键").tag(0)
                Text("效果").tag(1)
                Text("保存 & 动作").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Form {
                switch screenshotSegment {
                case 0:
                    Section("截图模式快捷键") {
                        ForEach(SettingsStore.HotKeyID.screenshotKeys) { id in
                            HotKeyRecorderView(
                                title: id.title,
                                chord: settings.hotKey(for: id)
                            ) { chord in
                                if let conflict = settings.setHotKey(chord, for: id) {
                                    appState.showToast("快捷键与「\(conflict.title)」冲突，已忽略")
                                } else {
                                    DispatchQueue.main.async { appState.reloadHotKeys() }
                                }
                            }
                        }
                    }
                    Section("说明") {
                        Text("选区：悬停高亮窗口并单击截取；拖拽选区域。松手后出现动作条。⌘=编辑 · ⌥=保存 · ⇧=钉图 · 双击=复制。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                case 1:
                    Section("选区") {
                        Toggle("显示十字辅助线", isOn: $ss.showCrosshair)
                        Toggle("截图时包含光标", isOn: $ss.captureCursor)
                    }
                    Section("导出效果") {
                        Toggle("添加阴影", isOn: $ss.addShadow)
                        if ss.addShadow {
                            HStack {
                                Text("阴影大小")
                                Slider(value: $ss.shadowRadius, in: 4...40, step: 1)
                                Text("\(Int(ss.shadowRadius))")
                                    .monospacedDigit()
                                    .frame(width: 28)
                            }
                        }
                        HStack {
                            Text("圆角")
                            Slider(value: $ss.cornerRadius, in: 0...32, step: 1)
                            Text("\(Int(ss.cornerRadius))")
                                .monospacedDigit()
                                .frame(width: 28)
                        }
                    }
                default:
                    Section("保存") {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("默认文件夹")
                                Text(settings.screenshotSaveDirectory)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            Button("选择…") { pickSaveDirectory() }
                            Button("还原") {
                                settings.screenshotSaveDirectory = SettingsStore.defaultSaveDirectory.path
                            }
                        }
                        Toggle("保存后在 Finder 中显示", isOn: $settings.openFinderAfterSave)
                        Toggle("保存时同时复制到剪贴板", isOn: $settings.copyAfterSave)
                        Toggle("截图时播放声效", isOn: $ss.playSound)
                    }
                    Section("默认完成动作") {
                        Picker("选区确认后", selection: $ss.defaultAction) {
                            ForEach(CaptureAfterAction.allCases) { a in
                                Text(a.title).tag(a)
                            }
                        }
                        Text("窗口单击直接使用默认动作；区域拖选松手弹出动作条。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Section("延时 / 预设尺寸") {
                        Stepper("延时全屏：\(ss.delaySeconds) 秒", value: $ss.delaySeconds, in: 1...15)
                        HStack {
                            Text("预设宽")
                            TextField("", value: $ss.presetWidth, format: .number)
                                .frame(width: 72)
                            Text("高")
                            TextField("", value: $ss.presetHeight, format: .number)
                                .frame(width: 72)
                        }
                    }
                    Section("编辑器") {
                        Text("进入编辑器后：马赛克、序号、钉图；⌘↩ 复制并关闭。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private var aiTab: some View {
        Form {
            Section("OpenAI 兼容接口") {
                TextField("Base URL", text: $settings.aiBaseURL)
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: $settings.aiModel)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    if showAPIKey {
                        TextField("API Key", text: $settings.apiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("API Key", text: $settings.apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(showAPIKey ? "隐藏" : "显示") { showAPIKey.toggle() }
                }
                Picker("默认目标语言", selection: $settings.targetLanguage) {
                    Text("中文").tag("zh")
                    Text("English").tag("en")
                    Text("日本語").tag("ja")
                    Text("한국어").tag("ko")
                    Text("Français").tag("fr")
                    Text("Deutsch").tag("de")
                    Text("Español").tag("es")
                }
            }
            Section("预设") {
                Button("DeepSeek 默认") {
                    settings.aiBaseURL = "https://api.deepseek.com/v1"
                    settings.aiModel = "deepseek-chat"
                }
                Button("OpenAI 兼容占位") {
                    settings.aiBaseURL = "https://api.openai.com/v1"
                    settings.aiModel = "gpt-4o-mini"
                }
            }
            Section("连通性") {
                Button {
                    Task { await testAI() }
                } label: {
                    if testingConnection {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("测试 API 连接")
                    }
                }
                .disabled(testingConnection)
                if let connectionMessage {
                    Text(connectionMessage)
                        .font(.caption)
                        .foregroundStyle(connectionMessage.contains("成功") ? .green : .red)
                        .textSelection(.enabled)
                }
            }
            Section("说明") {
                Text("API Key 保存在 macOS 钥匙串。支持任意 OpenAI Chat Completions 兼容服务。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var shortcutsTab: some View {
        Form {
            Section("全局快捷键") {
                ForEach(SettingsStore.HotKeyID.allCases) { id in
                    HotKeyRecorderView(
                        title: id.title,
                        chord: settings.hotKey(for: id)
                    ) { chord in
                        // Defer Carbon re-register out of the view update cycle
                        if let conflict = settings.setHotKey(chord, for: id) {
                            appState.showToast("快捷键与「\(conflict.title)」冲突，已忽略")
                        } else {
                            DispatchQueue.main.async {
                                appState.reloadHotKeys()
                            }
                        }
                    }
                }
            }
            Section {
                Button("恢复默认快捷键") {
                    settings.resetHotKeys()
                    DispatchQueue.main.async {
                        appState.reloadHotKeys()
                    }
                }
                Text("点击右侧按钮后按下组合键即可录制。Esc 取消录制。修改后立即生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // 不要在 onAppear 里 reloadHotKeys：会在视图切换时触发 Carbon 重注册导致闪退
    }

    private var permissionsTab: some View {
        Form {
            Section("状态") {
                HStack {
                    Label("屏幕录制", systemImage: "rectangle.dashed.badge.record")
                    Spacer()
                    Text(screenPermissionOK ? "已授权" : "未授权 / 未生效")
                        .foregroundStyle(screenPermissionOK ? .green : .orange)
                    Button("刷新") { Task { await refreshPermissions() } }
                }
                HStack {
                    Label("辅助功能", systemImage: "accessibility")
                    Spacer()
                    Text(accessibilityOK ? "已授权" : "未生效（若系统已开请退出重开）")
                        .foregroundStyle(accessibilityOK ? .green : .orange)
                    Button("刷新") { Task { await refreshPermissions() } }
                    Button("请求") {
                        PermissionHelper.requestAccessibilityPrompt()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            accessibilityOK = PermissionHelper.accessibilityStatusOK
                        }
                    }
                }
            }

            Section("录屏权限修复向导") {
                VStack(alignment: .leading, spacing: 10) {
                    repairRow(1, "确认只运行此路径的 zTools：")
                    Text(PermissionHelper.runningAppPath)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

                    HStack {
                        Button("复制路径") {
                            PasteboardUtil.copyString(PermissionHelper.runningAppPath)
                            appState.showToast("路径已复制")
                        }
                        Button("在 Finder 显示") {
                            NSWorkspace.shared.activateFileViewerSelecting([
                                URL(fileURLWithPath: PermissionHelper.runningAppPath)
                            ])
                        }
                    }

                    repairRow(2, "打开系统设置 → 录屏与系统录音")
                    Button("打开录屏设置") {
                        PermissionHelper.openScreenRecordingSettings()
                        repairStep = max(repairStep, 2)
                    }

                    repairRow(3, "删除列表中全部旧的 zTools，再点 + 只添加上面的路径并打开开关")

                    repairRow(4, "完全退出 zTools 后重新打开，再试截图")
                    Button("退出 zTools") {
                        NSApp.terminate(nil)
                    }

                    Button("请求系统授权弹窗") {
                        _ = PermissionHelper.requestScreenRecording()
                        Task {
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            await refreshPermissions()
                        }
                    }
                }
            }

            Section("辅助功能修复") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("开关已开仍显示未授权时，常见原因是授权绑到了旧的 build 路径。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(PermissionHelper.runningAppPath)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    HStack {
                        Button("打开辅助功能设置") {
                            PermissionHelper.openAccessibilitySettings()
                        }
                        Button("复制运行路径") {
                            PasteboardUtil.copyString(PermissionHelper.runningAppPath)
                            appState.showToast("路径已复制")
                        }
                    }
                    Text("在列表中移除旧 zTools，只保留上面路径并打开开关，然后完全退出再启动。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("说明") {
                Text("开关已开仍弹窗，通常是授权绑到了旧副本（build 目录）。请始终使用 ~/Applications/zTools.app，并用 scripts/install-and-run.sh 安装。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    ZToolsLogoMark(size: 64, showGlow: true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppVersionInfo.productName)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("截图 · OCR · 剪贴板 · 翻译 · 效率工具")
                            .foregroundStyle(.secondary)
                        Text("版本 \(AppVersionInfo.displayVersion)")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                GroupBox("软件信息") {
                    VStack(alignment: .leading, spacing: 8) {
                        infoRow("产品", AppVersionInfo.productName)
                        infoRow("版本", AppVersionInfo.shortVersion)
                        infoRow("Build", AppVersionInfo.build)
                        infoRow("Bundle ID", AppVersionInfo.bundleID)
                        infoRow("运行路径", PermissionHelper.runningAppPath)
                        infoRow("最低系统", "macOS 15+")
                        infoRow("版权", AppVersionInfo.copyright)
                    }
                    .padding(6)
                }

                GroupBox("更新内容") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(AppVersionInfo.changelog, id: \.version) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("v\(entry.version)")
                                        .font(.headline)
                                    Text(entry.date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(entry.items, id: \.self) { item in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("•")
                                            .foregroundStyle(.secondary)
                                        Text(item)
                                            .font(.callout)
                                    }
                                }
                            }
                            if entry.version != AppVersionInfo.changelog.last?.version {
                                Divider()
                            }
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("检查更新") {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            Task { await updater.check(manual: true) }
                        } label: {
                            if updater.isChecking {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("检查更新")
                            }
                        }
                        if let msg = updater.statusMessage {
                            Text(msg)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        if let latest = updater.latest {
                            Text("最新记录：v\(latest.version)")
                                .font(.caption.weight(.semibold))
                            Text(latest.notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let url = latest.url {
                                Link("打开发布页", destination: url)
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("URL Scheme / 自动化") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("可在终端、快捷指令、Alfred 中调用：")
                            .font(.callout)
                        ForEach([
                            "open 'ztools://screenshot'",
                            "open 'ztools://ocr'",
                            "open 'ztools://clipboard'",
                            "open 'ztools://translate?text=hello'",
                            "open 'ztools://color'",
                            "open 'ztools://palette'",
                            "open 'ztools://settings'"
                        ], id: \.self) { line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("推荐安装") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("唯一推荐路径：")
                        Text("~/Applications/zTools.app")
                            .font(.system(size: 12, design: .monospaced))
                        Text("安装 / 打包：")
                        Text("./scripts/install-and-run.sh")
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                        Text("./scripts/package-release.sh")
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                        Text("请勿直接运行工程 build/ 目录中的副本，以免录屏权限失效。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(6)
                }
            }
        }
    }

    private func repairRow(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.accentColor, in: Circle())
            Text(text)
                .font(.callout)
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
    }

    private func pickNotesDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.notesDirectoryURL
        panel.prompt = "选择"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                settings.notesDirectory = url.path
                appState.noteStore.setDirectory(url)
            }
        }
    }

    private func pickSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.screenshotSaveDirectoryURL
        panel.prompt = "选择"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                settings.screenshotSaveDirectory = url.path
            }
        }
    }

    private func refreshPermissions() async {
        screenPermissionOK = await PermissionHelper.canAccessScreenContent()
        // probe catches ad-hoc false negatives where AXIsProcessTrusted is flaky
        accessibilityOK = PermissionHelper.accessibilityStatusOK
    }

    private func testAI() async {
        testingConnection = true
        connectionMessage = nil
        defer { testingConnection = false }
        do {
            let sample = try await appState.translateService.testConnection()
            connectionMessage = "连接成功，示例返回：\(sample.prefix(40))"
        } catch {
            connectionMessage = error.localizedDescription
        }
    }
}
