import AppKit

enum RetinaImage {
    /// Best backing scale for an image (from bitmap reps or main screen).
    static func scale(of image: NSImage) -> CGFloat {
        var best: CGFloat = 1
        for rep in image.representations {
            let pw = CGFloat(rep.pixelsWide)
            let ph = CGFloat(rep.pixelsHigh)
            guard image.size.width > 0, image.size.height > 0 else { continue }
            let sx = pw / image.size.width
            let sy = ph / image.size.height
            best = max(best, max(sx, sy))
        }
        if best < 1.1 {
            best = NSScreen.main?.backingScaleFactor ?? 2
        }
        return best
    }

    /// Create NSImage from CGImage keeping full pixel density.
    static func from(cgImage: CGImage, pointSize: NSSize) -> NSImage {
        let image = NSImage(size: pointSize)
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = pointSize
        image.addRepresentation(rep)
        return image
    }

    /// High-DPI offscreen draw. `draw` uses **point** coordinates in a flipped=false Cocoa space.
    static func render(sizePoints: NSSize, scale: CGFloat, draw: (CGContext, CGFloat) -> Void) -> NSImage? {
        let scale = max(1, scale)
        let pw = max(1, Int((sizePoints.width * scale).rounded(.up)))
        let ph = max(1, Int((sizePoints.height * scale).rounded(.up)))
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
        rep.size = sizePoints

        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        ctx.shouldAntialias = true
        // Cocoa bottom-left, points
        ctx.cgContext.saveGState()
        draw(ctx.cgContext, scale)
        ctx.cgContext.restoreGState()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: sizePoints)
        image.addRepresentation(rep)
        return image
    }

    static func pngData(from image: NSImage) -> Data? {
        // Prefer the highest-resolution bitmap representation
        let reps = image.representations.compactMap { $0 as? NSBitmapImageRep }
        let best = reps.max(by: { ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh) })
        if let best {
            return best.representation(using: .png, properties: [:])
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Pixel-align a Cocoa rect on a given scale (reduces subpixel blur).
    static func alignRect(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let s = max(1, scale)
        let x = floor(rect.minX * s) / s
        let y = floor(rect.minY * s) / s
        let maxX = ceil(rect.maxX * s) / s
        let maxY = ceil(rect.maxY * s) / s
        return CGRect(x: x, y: y, width: max(1 / s, maxX - x), height: max(1 / s, maxY - y))
    }
}
