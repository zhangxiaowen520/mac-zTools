import AppKit
import SwiftUI

enum ZTheme {
    static let accent = Color(red: 1.0, green: 0.310, blue: 0.271)
    static let accentNS = NSColor(srgbRed: 1.0, green: 0.310, blue: 0.271, alpha: 1)

    static let radiusCard: CGFloat = 16
    static let radiusControl: CGFloat = 10
    static let radiusChip: CGFloat = 8
    static let radiusTile: CGFloat = 12
    static let pad: CGFloat = 16

    static let fill = Color.primary.opacity(0.06)
    static let fillQuiet = Color.primary.opacity(0.04)
    static let selectionFill = accent.opacity(0.14)
    static let selectionStroke = accent.opacity(0.35)

    static var hairline: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.22),
                Color.white.opacity(0.06),
                Color.black.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static let shadowColor = Color.black.opacity(0.20)
    static let shadowRadius: CGFloat = 28
    static let shadowY: CGFloat = 12

    static let springPanel = Animation.spring(duration: 0.28, bounce: 0.12)
    static let springIsland = Animation.spring(duration: 0.42, bounce: 0.18)
}
