import AppKit
import SwiftUI

struct AnnotationCanvas: View {
    let image: NSImage
    @Binding var strokes: [AnnotationStroke]
    @Binding var draft: AnnotationStroke?
    let tool: AnnotationTool
    let color: Color
    let lineWidth: CGFloat
    let nextNumber: Int
    let onCommitDraft: () -> Void
    let onRequestText: (CGPoint) -> Void
    let onRequestNumber: (CGPoint) -> Void

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let fit = fittedRect(imageSize: image.size, in: geo.size)
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001)
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: fit.width, height: fit.height)
                    .position(x: fit.midX, y: fit.midY)

                Canvas { context, _ in
                    for stroke in strokes {
                        draw(stroke, in: &context, imageRect: fit)
                    }
                    if let draft {
                        draw(draft, in: &context, imageRect: fit)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let p = clamp(value.location, in: fit)
                        if !isDragging {
                            isDragging = true
                            if tool == .text || tool == .number {
                                return
                            }
                            draft = AnnotationStroke(
                                tool: tool,
                                points: [p],
                                color: color,
                                lineWidth: lineWidth,
                                number: nextNumber
                            )
                        } else if tool != .text && tool != .number {
                            updateDraft(to: p, tool: tool)
                        }
                    }
                    .onEnded { value in
                        defer { isDragging = false }
                        let p = clamp(value.location, in: fit)
                        if tool == .text {
                            onRequestText(p)
                            return
                        }
                        if tool == .number {
                            onRequestNumber(p)
                            return
                        }
                        updateDraft(to: p, tool: tool)
                        onCommitDraft()
                    }
            )
        }
    }

    private func updateDraft(to point: CGPoint, tool: AnnotationTool) {
        guard var current = draft else { return }
        switch tool {
        case .pen:
            current.points.append(point)
        default:
            if current.points.isEmpty {
                current.points = [point, point]
            } else if current.points.count == 1 {
                current.points.append(point)
            } else {
                current.points[current.points.count - 1] = point
            }
        }
        draft = current
    }

    private func clamp(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    private func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func draw(_ stroke: AnnotationStroke, in context: inout GraphicsContext, imageRect: CGRect) {
        let start = stroke.start
        let end = stroke.end
        var path = Path()

        switch stroke.tool {
        case .rect, .highlight, .mosaic:
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            path.addRect(rect)
            if stroke.tool == .highlight {
                context.fill(path, with: .color(stroke.color.opacity(0.35)))
            } else if stroke.tool == .mosaic {
                drawMosaicPreview(rect: rect, block: max(6, stroke.lineWidth * 3), in: &context)
            } else {
                context.stroke(path, with: .color(stroke.color), lineWidth: stroke.lineWidth)
            }

        case .oval:
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            path.addEllipse(in: rect)
            context.stroke(path, with: .color(stroke.color), lineWidth: stroke.lineWidth)

        case .line:
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(stroke.color), style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round))

        case .arrow:
            let shaftW = max(stroke.lineWidth * 1.8, 4)
            let headLen = max(22, shaftW * 5.5)
            let headHalf = headLen * 0.42
            let geom = arrowGeometry(from: start, to: end, headLength: headLen, headHalfWidth: headHalf)
            var shaft = Path()
            shaft.move(to: start)
            shaft.addLine(to: geom.shaftEnd)
            context.stroke(shaft, with: .color(stroke.color), style: StrokeStyle(lineWidth: shaftW, lineCap: .butt, lineJoin: .miter))
            context.fill(geom.head, with: .color(stroke.color))

        case .pen:
            guard let first = stroke.points.first else { return }
            path.move(to: first)
            for point in stroke.points.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(path, with: .color(stroke.color), style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round))

        case .number:
            let r: CGFloat = max(14, stroke.lineWidth * 5)
            let circle = Path(ellipseIn: CGRect(x: start.x - r, y: start.y - r, width: r * 2, height: r * 2))
            context.fill(circle, with: .color(stroke.color))
            let label = Text("\(stroke.number)")
                .font(.system(size: r * 0.95, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            context.draw(label, at: start, anchor: .center)

        case .text:
            let text = Text(stroke.text.isEmpty ? "文字" : stroke.text)
                .font(.system(size: max(14, stroke.lineWidth * 5), weight: .semibold))
                .foregroundStyle(stroke.color)
            context.draw(text, at: start, anchor: .topLeading)
        }

        _ = imageRect
    }

    private func drawMosaicPreview(rect: CGRect, block: CGFloat, in context: inout GraphicsContext) {
        guard rect.width > 1, rect.height > 1 else { return }
        var y = rect.minY
        var row = 0
        while y < rect.maxY {
            var x = rect.minX
            var col = 0
            let h = min(block, rect.maxY - y)
            while x < rect.maxX {
                let w = min(block, rect.maxX - x)
                let shade = 0.25 + Double((row + col) % 5) * 0.1
                var cell = Path(CGRect(x: x, y: y, width: w, height: h))
                context.fill(cell, with: .color(Color.gray.opacity(shade)))
                x += block
                col += 1
            }
            y += block
            row += 1
        }
        context.stroke(Path(rect), with: .color(Color.white.opacity(0.25)), lineWidth: 1)
    }

    /// 粗箭身 + 大号实心三角箭头（对齐常见标注工具视觉）
    private func arrowGeometry(from start: CGPoint, to end: CGPoint, headLength: CGFloat, headHalfWidth: CGFloat) -> (shaftEnd: CGPoint, head: Path) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(0.001, hypot(dx, dy))
        let ux = dx / length
        let uy = dy / length
        let px = -uy
        let py = ux
        // 箭身止于箭头底部，避免穿出箭头
        let usableHead = min(headLength, length * 0.45)
        let half = max(headHalfWidth, usableHead * 0.4)
        let base = CGPoint(x: end.x - ux * usableHead, y: end.y - uy * usableHead)
        let left = CGPoint(x: base.x + px * half, y: base.y + py * half)
        let right = CGPoint(x: base.x - px * half, y: base.y - py * half)
        // 略微内收底部，箭头更「尖」更实
        let inset = usableHead * 0.12
        let baseCenter = CGPoint(x: end.x - ux * (usableHead - inset), y: end.y - uy * (usableHead - inset))
        var head = Path()
        head.move(to: end)
        head.addLine(to: left)
        head.addLine(to: baseCenter)
        head.addLine(to: right)
        head.closeSubpath()
        return (baseCenter, head)
    }
}

enum AnnotationRenderer {
    @MainActor
    static func render(image: NSImage, strokes: [AnnotationStroke], canvasSize: CGSize) -> NSImage {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return image }

        let scale = min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (canvasSize.width - drawSize.width) / 2,
            y: (canvasSize.height - drawSize.height) / 2
        )
        let fit = CGRect(origin: origin, size: drawSize)

        // 使用源图最高像素密度导出，避免标注合成时降采样
        let scaleFactor = RetinaImage.scale(of: image)
        let exportPixels = CGSize(
            width: max(1, (imageSize.width * scaleFactor).rounded()),
            height: max(1, (imageSize.height * scaleFactor).rounded())
        )

        guard let baseRep = bitmapRep(from: image, pixelSize: exportPixels, pointSize: imageSize) else { return image }

        // Canvas(y-down) → image point space (y-down)
        let unitScale = imageSize.width / max(fit.width, 1)

        func mapToImagePoints(_ p: CGPoint) -> CGPoint {
            CGPoint(
                x: (p.x - fit.minX) / max(fit.width, 1) * imageSize.width,
                y: (p.y - fit.minY) / max(fit.height, 1) * imageSize.height
            )
        }

        // Mosaic works in pixel space (y-up for bitmap)
        for stroke in strokes where stroke.tool == .mosaic {
            let a = mapToImagePoints(stroke.start)
            let b = mapToImagePoints(stroke.end)
            let minY = min(a.y, b.y)
            let maxY = max(a.y, b.y)
            let rectPts = CGRect(
                x: min(a.x, b.x),
                y: minY,
                width: abs(b.x - a.x),
                height: abs(b.y - a.y)
            )
            // Convert point-space y-down rect → pixel y-up
            let rectPx = CGRect(
                x: rectPts.minX * scaleFactor,
                y: (imageSize.height - rectPts.maxY) * scaleFactor,
                width: rectPts.width * scaleFactor,
                height: rectPts.height * scaleFactor
            )
            let block = max(4, stroke.lineWidth * 3 * unitScale * scaleFactor)
            applyMosaic(to: baseRep, rect: rectPx, blockSize: Int(block.rounded()))
        }

        // Vector drawing uses point coordinates (rep.size)
        guard let nsCtx = NSGraphicsContext(bitmapImageRep: baseRep) else {
            let fallback = NSImage(size: imageSize)
            fallback.addRepresentation(baseRep)
            return fallback
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        nsCtx.imageInterpolation = .high
        defer { NSGraphicsContext.restoreGraphicsState() }

        // point-space y-down → Cocoa y-up
        func cocoa(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x, y: imageSize.height - p.y)
        }

        for stroke in strokes where stroke.tool != .mosaic {
            let pts = stroke.points.map { cocoa(mapToImagePoints($0)) }
            guard let start = pts.first else { continue }
            let end = pts.last ?? start
            let nsColor = NSColor(stroke.color)
            nsColor.setStroke()
            nsColor.setFill()
            let lw = max(1, stroke.lineWidth * unitScale)

            switch stroke.tool {
            case .rect:
                let rect = CGRect(
                    x: min(start.x, end.x), y: min(start.y, end.y),
                    width: abs(end.x - start.x), height: abs(end.y - start.y)
                )
                let path = NSBezierPath(rect: rect)
                path.lineWidth = lw
                path.stroke()

            case .highlight:
                let rect = CGRect(
                    x: min(start.x, end.x), y: min(start.y, end.y),
                    width: abs(end.x - start.x), height: abs(end.y - start.y)
                )
                nsColor.withAlphaComponent(0.35).setFill()
                NSBezierPath(rect: rect).fill()

            case .oval:
                let rect = CGRect(
                    x: min(start.x, end.x), y: min(start.y, end.y),
                    width: abs(end.x - start.x), height: abs(end.y - start.y)
                )
                let path = NSBezierPath(ovalIn: rect)
                path.lineWidth = lw
                path.stroke()

            case .line:
                let path = NSBezierPath()
                path.move(to: start)
                path.line(to: end)
                path.lineWidth = lw
                path.lineCapStyle = .round
                path.stroke()

            case .arrow:
                let shaftW = max(lw * 1.8, 4)
                let headLen = max(22, shaftW * 5.5)
                let headHalf = headLen * 0.42
                let geom = arrowGeometryNS(from: start, to: end, headLength: headLen, headHalfWidth: headHalf)
                let path = NSBezierPath()
                path.move(to: start)
                path.line(to: geom.shaftEnd)
                path.lineWidth = shaftW
                path.lineCapStyle = .butt
                path.lineJoinStyle = .miter
                path.stroke()
                nsColor.setFill()
                geom.head.fill()

            case .pen:
                let path = NSBezierPath()
                path.move(to: start)
                for p in pts.dropFirst() { path.line(to: p) }
                path.lineWidth = lw
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()

            case .number:
                let r = max(14, stroke.lineWidth * 5) * unitScale
                let circle = NSBezierPath(ovalIn: CGRect(x: start.x - r, y: start.y - r, width: r * 2, height: r * 2))
                nsColor.setFill()
                circle.fill()
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: r * 0.95, weight: .bold),
                    .foregroundColor: NSColor.white
                ]
                let str = "\(stroke.number)" as NSString
                let ts = str.size(withAttributes: attrs)
                str.draw(at: CGPoint(x: start.x - ts.width / 2, y: start.y - ts.height / 2), withAttributes: attrs)

            case .text:
                let fontSize = max(14, stroke.lineWidth * 5) * unitScale
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                    .foregroundColor: nsColor
                ]
                let string = stroke.text.isEmpty ? "文字" : stroke.text
                let textSize = string.size(withAttributes: attrs)
                string.draw(at: CGPoint(x: start.x, y: start.y - textSize.height), withAttributes: attrs)

            case .mosaic:
                break
            }
        }

        let output = NSImage(size: imageSize)
        output.addRepresentation(baseRep)
        return output
    }

    private static func bitmapRep(from image: NSImage, pixelSize: CGSize, pointSize: CGSize) -> NSBitmapImageRep? {
        let pw = max(1, Int(pixelSize.width.rounded()))
        let ph = max(1, Int(pixelSize.height.rounded()))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pw,
            pixelsHigh: ph,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = pointSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        // 画满整个像素缓冲（坐标系为 pointSize）
        image.draw(
            in: CGRect(origin: .zero, size: pointSize),
            from: CGRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func applyMosaic(to rep: NSBitmapImageRep, rect: CGRect, blockSize: Int) {
        let block = max(4, blockSize)
        let minX = max(0, Int(rect.minX.rounded(.down)))
        let minY = max(0, Int(rect.minY.rounded(.down)))
        let maxX = min(rep.pixelsWide, Int(rect.maxX.rounded(.up)))
        let maxY = min(rep.pixelsHigh, Int(rect.maxY.rounded(.up)))
        guard maxX > minX, maxY > minY else { return }

        var y = minY
        while y < maxY {
            var x = minX
            let y2 = min(y + block, maxY)
            while x < maxX {
                let x2 = min(x + block, maxX)
                var r = 0, g = 0, b = 0, a = 0, count = 0
                for py in y..<y2 {
                    for px in x..<x2 {
                        guard let c = rep.colorAt(x: px, y: py) else { continue }
                        r += Int(c.redComponent * 255)
                        g += Int(c.greenComponent * 255)
                        b += Int(c.blueComponent * 255)
                        a += Int(c.alphaComponent * 255)
                        count += 1
                    }
                }
                if count > 0 {
                    let avg = NSColor(
                        red: CGFloat(r / count) / 255,
                        green: CGFloat(g / count) / 255,
                        blue: CGFloat(b / count) / 255,
                        alpha: CGFloat(a / count) / 255
                    )
                    for py in y..<y2 {
                        for px in x..<x2 {
                            rep.setColor(avg, atX: px, y: py)
                        }
                    }
                }
                x = x2
            }
            y = y2
        }
    }

    private static func arrowGeometryNS(from start: CGPoint, to end: CGPoint, headLength: CGFloat, headHalfWidth: CGFloat) -> (shaftEnd: CGPoint, head: NSBezierPath) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(0.001, hypot(dx, dy))
        let ux = dx / length
        let uy = dy / length
        let px = -uy
        let py = ux
        let usableHead = min(headLength, length * 0.45)
        let half = max(headHalfWidth, usableHead * 0.4)
        let base = CGPoint(x: end.x - ux * usableHead, y: end.y - uy * usableHead)
        let left = CGPoint(x: base.x + px * half, y: base.y + py * half)
        let right = CGPoint(x: base.x - px * half, y: base.y - py * half)
        let inset = usableHead * 0.12
        let baseCenter = CGPoint(x: end.x - ux * (usableHead - inset), y: end.y - uy * (usableHead - inset))
        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: left)
        head.line(to: baseCenter)
        head.line(to: right)
        head.close()
        return (baseCenter, head)
    }
}
