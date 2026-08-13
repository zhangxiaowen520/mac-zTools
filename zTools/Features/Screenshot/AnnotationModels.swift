import AppKit
import SwiftUI

enum AnnotationTool: String, CaseIterable, Identifiable {
    case rect
    case oval
    case arrow
    case line
    case pen
    case highlight
    case mosaic
    case number
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rect: "矩形"
        case .oval: "椭圆"
        case .arrow: "箭头"
        case .line: "直线"
        case .pen: "画笔"
        case .highlight: "高亮"
        case .mosaic: "马赛克"
        case .number: "序号"
        case .text: "文字"
        }
    }

    var systemImage: String {
        switch self {
        case .rect: "rectangle"
        case .oval: "oval"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .pen: "pencil.tip"
        case .highlight: "highlighter"
        case .mosaic: "square.grid.3x3.fill"
        case .number: "number.circle"
        case .text: "textformat"
        }
    }
}

struct AnnotationStroke: Identifiable, Equatable {
    let id: UUID
    var tool: AnnotationTool
    var points: [CGPoint]
    var color: Color
    var lineWidth: CGFloat
    var text: String
    var number: Int

    init(
        id: UUID = UUID(),
        tool: AnnotationTool,
        points: [CGPoint],
        color: Color,
        lineWidth: CGFloat,
        text: String = "",
        number: Int = 0
    ) {
        self.id = id
        self.tool = tool
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.text = text
        self.number = number
    }

    var start: CGPoint { points.first ?? .zero }
    var end: CGPoint { points.last ?? start }
}

enum AnnotationPalette {
    static let colors: [Color] = [
        .red, .orange, .yellow, .green, .mint, .cyan, .blue, .purple, .pink, .white, .black
    ]
    static let lineWidths: [CGFloat] = [2, 3, 5, 8, 12]
}

/// 标注的可持久化表示（用于草稿续编），避免给 Color/CGPoint 加全局 Codable。
struct StoredAnnotationStroke: Codable {
    let tool: String
    let points: [[CGFloat]]
    let colorHex: String
    let lineWidth: CGFloat
    let text: String
    let number: Int

    init(_ stroke: AnnotationStroke) {
        tool = stroke.tool.rawValue
        points = stroke.points.map { [$0.x, $0.y] }
        colorHex = NSColor(stroke.color).hexString
        lineWidth = stroke.lineWidth
        text = stroke.text
        number = stroke.number
    }

    func toStroke() -> AnnotationStroke? {
        guard let tool = AnnotationTool(rawValue: tool) else { return nil }
        let pts = points.compactMap { pair -> CGPoint? in
            guard pair.count == 2 else { return nil }
            return CGPoint(x: pair[0], y: pair[1])
        }
        return AnnotationStroke(
            tool: tool,
            points: pts,
            color: Color(nsColor: NSColor(hex: colorHex) ?? .red),
            lineWidth: lineWidth,
            text: text,
            number: number
        )
    }
}

enum AppVersionInfo {
    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.5.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "5"
    }

    static var displayVersion: String {
        "\(shortVersion) (\(build))"
    }

    static let productName = "zTools"
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.zeno.ztools"
    static let copyright = "Copyright © 2026 zeno. All rights reserved."

    static let changelog: [(version: String, date: String, items: [String])] = [
        (
            "0.5.0",
            "2026-08-10",
            [
                "截图模式：选区/全屏/延时/光标下窗口/上次区域/预设尺寸",
                "选区 HUD：十字线、窗口高亮、尺寸、完成后动作条",
                "默认动作与修饰键：⌘编辑 · ⌥保存 · ⇧钉图 · 双击复制",
                "导出圆角与阴影、截图声效",
                "设置截图三页：模式快捷键 / 效果 / 保存与动作"
            ]
        ),
        (
            "0.4.0",
            "2026-08-10",
            [
                "URL Scheme：ztools://screenshot|ocr|clipboard|translate|color|palette|settings",
                "取色：历史色板，导出 HEX/CSS/SwiftUI/UIColor",
                "时间戳：多格式代码片段、时区收藏",
                "关于页检查更新（内置 changelog / 可接 GitHub Releases）",
                "package-release 打包脚本"
            ]
        ),
        (
            "0.3.0",
            "2026-08-10",
            [
                "剪贴板：来源 App、键盘导航、⌘1-9 快贴、预览、一键翻译",
                "敏感内容启发式跳过（密码管理器 / concealed）",
                "划词翻译（⌘⇧E）与命令面板（⌘K）",
                "OCR / 剪贴板 → 翻译闭环",
                "翻译连通性测试与错误中文化",
                "悬浮球贴边半透明、全屏自动隐藏"
            ]
        ),
        (
            "0.2.0",
            "2026-08-10",
            [
                "截图编辑：马赛克、序号标记",
                "复制并关闭（⌘↩）作为默认完成动作",
                "钉图：截图置顶悬浮预览",
                "设置：关于页、权限修复向导",
                "悬浮球品牌 Logo 与无边框工具面板"
            ]
        ),
        (
            "0.1.0",
            "2026-08-10",
            [
                "菜单栏 + 悬浮球启动",
                "截图选区、标注、OCR、剪贴板、翻译、时间戳、取色",
                "DeepSeek / OpenAI 兼容翻译",
                "全局快捷键与设置窗口"
            ]
        )
    ]
}

enum ScreenshotExport {
    static func pngData(from image: NSImage) -> Data? {
        RetinaImage.pngData(from: image)
    }

    static func savePNG(_ image: NSImage, to url: URL) throws {
        guard let data = pngData(from: image) else {
            throw ScreenshotError.failed
        }
        try data.write(to: url, options: .atomic)
    }
}
