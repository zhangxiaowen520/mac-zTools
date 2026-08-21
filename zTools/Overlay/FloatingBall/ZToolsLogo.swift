import AppKit
import SwiftUI

struct ZToolsLogoMark: View {
    var size: CGFloat = 48
    var showGlow: Bool = true
    var compact: Bool = false

    var body: some View {
        ZStack {
            if showGlow {
                Circle()
                    .fill(ZTheme.accent.opacity(0.22))
                    .frame(width: size * 1.22, height: size * 1.22)
                    .blur(radius: size * 0.12)
            }

            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: size, height: size)

            Circle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: size, height: size)

            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.45),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
                .frame(width: size, height: size)

            Ellipse()
                .fill(Color.white.opacity(0.28))
                .frame(width: size * 0.5, height: size * 0.22)
                .offset(y: -size * 0.18)
                .blur(radius: 0.5)

            ZMarkShape()
                .fill(Color.primary.opacity(0.92))
                .frame(width: size * 0.42, height: size * 0.42)
        }
        .frame(width: size, height: size)
        .compositingGroup()
    }
}

struct ZMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let t = min(w, h) * 0.22
        let r = t * 0.35

        var path = Path()
        path.addRoundedRect(
            in: CGRect(x: 0, y: 0, width: w, height: t),
            cornerSize: CGSize(width: r, height: r)
        )
        path.addRoundedRect(
            in: CGRect(x: 0, y: h - t, width: w, height: t),
            cornerSize: CGSize(width: r, height: r)
        )
        var slash = Path()
        let topRight = CGPoint(x: w, y: t * 0.55)
        let topLeft = CGPoint(x: w - t * 1.15, y: t * 0.55)
        let bottomLeft = CGPoint(x: 0, y: h - t * 0.55)
        let bottomRight = CGPoint(x: t * 1.15, y: h - t * 0.55)
        slash.move(to: topLeft)
        slash.addLine(to: topRight)
        slash.addLine(to: bottomRight)
        slash.addLine(to: bottomLeft)
        slash.closeSubpath()
        path.addPath(slash)
        return path
    }
}

struct ZToolsLogoBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            ZToolsLogoMark(size: 22, showGlow: false, compact: true)
            Text("zTools")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }
}

struct MenuBarZMark: View {
    var body: some View {
        Image(nsImage: Self.template)
    }

    private static let template: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        let path = NSBezierPath()
        path.lineWidth = 1.8
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: 3.2, y: 14.2))
        path.line(to: NSPoint(x: 14.8, y: 14.2))
        path.line(to: NSPoint(x: 3.2, y: 3.8))
        path.line(to: NSPoint(x: 14.8, y: 3.8))
        NSColor.black.setStroke()
        path.stroke()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }()
}
