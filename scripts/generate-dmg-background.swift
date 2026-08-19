import AppKit

let width: CGFloat = 1320
let height: CGFloat = 840
let scale: CGFloat = 2

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(width),
    pixelsHigh: Int(height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("failed to create bitmap\n", stderr)
    exit(1)
}
rep.size = NSSize(width: width / scale, height: height / scale)

guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
    fputs("failed to create context\n", stderr)
    exit(1)
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
let g = ctx.cgContext
let w = width / scale
let h = height / scale

let bg = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(srgbRed: 0.10, green: 0.09, blue: 0.16, alpha: 1).cgColor,
        NSColor(srgbRed: 0.16, green: 0.12, blue: 0.26, alpha: 1).cgColor,
        NSColor(srgbRed: 0.12, green: 0.08, blue: 0.16, alpha: 1).cgColor
    ] as CFArray,
    locations: [0, 0.55, 1]
)!
g.drawLinearGradient(bg, start: .zero, end: CGPoint(x: w, y: h), options: [])

let glow = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(srgbRed: 0.55, green: 0.35, blue: 1.0, alpha: 0.22).cgColor,
        NSColor(srgbRed: 0.95, green: 0.28, blue: 0.62, alpha: 0.0).cgColor
    ] as CFArray,
    locations: [0, 1]
)!
g.drawRadialGradient(
    glow,
    startCenter: CGPoint(x: w * 0.32, y: h * 0.38),
    startRadius: 0,
    endCenter: CGPoint(x: w * 0.32, y: h * 0.38),
    endRadius: 180,
    options: []
)
g.drawRadialGradient(
    glow,
    startCenter: CGPoint(x: w * 0.72, y: h * 0.42),
    startRadius: 0,
    endCenter: CGPoint(x: w * 0.72, y: h * 0.42),
    endRadius: 160,
    options: []
)

func drawArrow() {
    let path = NSBezierPath()
    let cx: CGFloat = w / 2
    let cy: CGFloat = 188
    path.move(to: CGPoint(x: cx - 36, y: cy))
    path.line(to: CGPoint(x: cx + 18, y: cy))
    path.lineWidth = 5
    path.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.55).setStroke()
    path.stroke()

    let head = NSBezierPath()
    head.move(to: CGPoint(x: cx + 14, y: cy - 14))
    head.line(to: CGPoint(x: cx + 38, y: cy))
    head.line(to: CGPoint(x: cx + 14, y: cy + 14))
    head.lineWidth = 5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()
}
drawArrow()

func drawText(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color
    ]
    let text = NSAttributedString(string: string, attributes: attrs)
    let tw = text.size().width
    text.draw(at: CGPoint(x: (w - tw) / 2, y: y))
}

drawText("安装 zTools", size: 22, weight: .semibold, color: .white, y: 338)
drawText("将 zTools 拖到「应用程序」即可完成安装", size: 13, weight: .medium, color: NSColor.white.withAlphaComponent(0.62), y: 58)

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    fputs("failed to encode png\n", stderr)
    exit(1)
}

let out = CommandLine.arguments.dropFirst().first ?? "background.png"
try data.write(to: URL(fileURLWithPath: out))
print("wrote \(out) (\(data.count) bytes)")
