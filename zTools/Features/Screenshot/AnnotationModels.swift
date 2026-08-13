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
