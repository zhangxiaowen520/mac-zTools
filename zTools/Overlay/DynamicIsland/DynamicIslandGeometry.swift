import CoreGraphics
import Foundation

struct IslandMetrics: Equatable {
    var screenWidth: CGFloat
    var hasNotch: Bool
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var notchMidX: CGFloat
    var menuBarHeight: CGFloat

    static let expandedWidth: CGFloat = 560
    static let toolsHeight: CGFloat = 264
    static let contentHeight: CGFloat = 468
    static let expandedHeight: CGFloat = contentHeight
    static let wingWidth: CGFloat = 58
    static let collapsedPeek: CGFloat = 6
    static let maxTopRadius: CGFloat = 32
    static let bouncePad: CGFloat = 36

    var collapsedHeight: CGFloat {
        if hasNotch {
            return notchHeight + Self.collapsedPeek
        }
        return 34
    }

    var collapsedWidth: CGFloat {
        if hasNotch {
            return notchWidth + Self.wingWidth * 2
        }
        return 220
    }

    var windowSize: CGSize {
        CGSize(width: max(screenWidth, 320), height: Self.expandedHeight + Self.bouncePad)
    }

    func islandSize(expanded: Bool, height: CGFloat? = nil) -> CGSize {
        if expanded {
            return CGSize(
                width: min(Self.expandedWidth, screenWidth - 24),
                height: height ?? Self.expandedHeight
            )
        }
        return CGSize(
            width: min(collapsedWidth, screenWidth - 24),
            height: collapsedHeight
        )
    }

    func islandRect(expanded: Bool, height: CGFloat? = nil) -> CGRect {
        let size = islandSize(expanded: expanded, height: height)
        let win = windowSize
        return CGRect(
            x: notchMidX - size.width / 2,
            y: win.height - size.height,
            width: size.width,
            height: size.height
        )
    }

    func hitRect(expanded: Bool, height: CGFloat? = nil) -> CGRect {
        var rect = islandRect(expanded: expanded, height: height)
        if !expanded {
            rect.size.height += 12
            rect.origin.y -= 12
        }
        return rect
    }

    static func make(
        screenWidth: CGFloat,
        visibleTopInset: CGFloat,
        safeAreaTop: CGFloat,
        notchWidth: CGFloat = 0,
        notchHeight: CGFloat = 0,
        notchMidX: CGFloat? = nil
    ) -> IslandMetrics {
        let measured = notchWidth > 1
        let hasNotch = measured || safeAreaTop > 0
        let menuBarHeight = max(visibleTopInset, 24)
        let resolvedHeight: CGFloat = {
            if notchHeight > 0 { return notchHeight }
            if hasNotch { return max(safeAreaTop, menuBarHeight) }
            return 0
        }()
        let resolvedWidth = measured
            ? notchWidth
            : estimatedNotchWidth(screenWidth: screenWidth, hasNotch: hasNotch)
        return IslandMetrics(
            screenWidth: screenWidth,
            hasNotch: hasNotch,
            notchWidth: resolvedWidth,
            notchHeight: resolvedHeight,
            notchMidX: notchMidX ?? screenWidth / 2,
            menuBarHeight: menuBarHeight
        )
    }

    static func estimatedNotchWidth(screenWidth: CGFloat, hasNotch: Bool) -> CGFloat {
        guard hasNotch else { return 0 }
        switch screenWidth {
        case 1440...1490: return 160
        case 1510...1540: return 185
        case 1680...1740: return 185
        case 1790...1820: return 185
        case 2040...2070: return 200
        default:
            return screenWidth < 1500 ? 160 : 185
        }
    }
}
