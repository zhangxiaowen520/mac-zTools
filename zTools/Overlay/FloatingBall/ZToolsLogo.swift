import SwiftUI

/// zTools 品牌标识：渐变圆 + 几何 Z 标
struct ZToolsLogoMark: View {
    var size: CGFloat = 48
    var showGlow: Bool = true
    var compact: Bool = false

    var body: some View {
        ZStack {
            if showGlow {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.45, green: 0.35, blue: 1.0).opacity(0.55),
                                Color(red: 0.95, green: 0.25, blue: 0.65).opacity(0.0)
                            ],
                            center: .center,
                            startRadius: size * 0.1,
                            endRadius: size * 0.72
                        )
                    )
                    .frame(width: size * 1.35, height: size * 1.35)
                    .blur(radius: size * 0.08)
            }

            // 外环高光
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.28),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            // 主体渐变
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.42, green: 0.38, blue: 1.00),
                            Color(red: 0.62, green: 0.28, blue: 0.98),
                            Color(red: 0.95, green: 0.28, blue: 0.62)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size - 1.5, height: size - 1.5)
                .overlay(
                    // 顶部内高光
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.55),
                                    Color.white.opacity(0.05),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: size * 0.045
                        )
                        .padding(size * 0.04)
                )
                .overlay(
                    // 玻璃高光斑
                    Ellipse()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.55),
                                    Color.white.opacity(0.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: size * 0.55, height: size * 0.28)
                        .offset(y: -size * 0.18)
                        .blur(radius: 0.5)
                )

            // Z 几何标
            ZMarkShape()
                .fill(Color.white)
                .frame(width: size * 0.46, height: size * 0.46)
                .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)

            if !compact {
                // 细描边
                Circle()
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .compositingGroup()
    }
}

/// 圆角几何 Z
struct ZMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let t = min(w, h) * 0.22 // 笔画粗细
        let r = t * 0.35

        var path = Path()

        // 顶横
        path.addRoundedRect(
            in: CGRect(x: 0, y: 0, width: w, height: t),
            cornerSize: CGSize(width: r, height: r)
        )
        // 底横
        path.addRoundedRect(
            in: CGRect(x: 0, y: h - t, width: w, height: t),
            cornerSize: CGSize(width: r, height: r)
        )
        // 斜杠（用四边形）
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
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
    }
}
