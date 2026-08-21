import XCTest
@testable import zTools

final class DynamicIslandGeometryTests: XCTestCase {
    func testCollapsedWiderThanNotch() {
        let metrics = IslandMetrics.make(
            screenWidth: 1728,
            visibleTopInset: 33,
            safeAreaTop: 32,
            notchWidth: 185,
            notchHeight: 32,
            notchMidX: 864
        )
        XCTAssertTrue(metrics.hasNotch)
        XCTAssertEqual(metrics.collapsedWidth, 185 + IslandMetrics.wingWidth * 2, accuracy: 0.001)
        XCTAssertGreaterThan(metrics.collapsedWidth, metrics.notchWidth)
        XCTAssertEqual(metrics.collapsedHeight, 38, accuracy: 0.001)
    }

    func testNoNotchStandalonePill() {
        let metrics = IslandMetrics.make(screenWidth: 1920, visibleTopInset: 24, safeAreaTop: 0)
        XCTAssertFalse(metrics.hasNotch)
        XCTAssertEqual(metrics.notchWidth, 0, accuracy: 0.001)
        XCTAssertGreaterThan(metrics.collapsedWidth, 100)
    }

    func testExpandedLargerThanCollapsed() {
        let metrics = IslandMetrics.make(
            screenWidth: 1512,
            visibleTopInset: 24,
            safeAreaTop: 32,
            notchWidth: 185,
            notchHeight: 32
        )
        let collapsed = metrics.islandSize(expanded: false)
        let expanded = metrics.islandSize(expanded: true)
        XCTAssertGreaterThan(expanded.width, collapsed.width)
        XCTAssertGreaterThan(expanded.height, collapsed.height)
        XCTAssertEqual(expanded.width, IslandMetrics.expandedWidth, accuracy: 0.001)
        XCTAssertEqual(expanded.height, IslandMetrics.expandedHeight, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(expanded.width, 500)
        XCTAssertGreaterThanOrEqual(expanded.height, 360)
    }

    func testIslandCenteredOnNotchAndFlushTop() {
        let metrics = IslandMetrics.make(
            screenWidth: 1728,
            visibleTopInset: 33,
            safeAreaTop: 32,
            notchWidth: 185,
            notchHeight: 32,
            notchMidX: 864
        )
        let rect = metrics.islandRect(expanded: false)
        XCTAssertEqual(rect.midX, 864, accuracy: 0.5)
        XCTAssertEqual(rect.maxY, metrics.windowSize.height, accuracy: 0.001)
        XCTAssertEqual(rect.width, metrics.collapsedWidth, accuracy: 0.001)
        XCTAssertEqual(rect.height, metrics.collapsedHeight, accuracy: 0.001)
    }

    func testUsesMeasuredNotchWidthOverEstimate() {
        let metrics = IslandMetrics.make(
            screenWidth: 1728,
            visibleTopInset: 33,
            safeAreaTop: 32,
            notchWidth: 177,
            notchHeight: 32
        )
        XCTAssertEqual(metrics.notchWidth, 177, accuracy: 0.001)
        XCTAssertEqual(metrics.collapsedWidth, 177 + IslandMetrics.wingWidth * 2, accuracy: 0.001)
    }

    func testEstimatedNotchWidthKnownModels() {
        XCTAssertEqual(IslandMetrics.estimatedNotchWidth(screenWidth: 1512, hasNotch: true), 185)
        XCTAssertEqual(IslandMetrics.estimatedNotchWidth(screenWidth: 1728, hasNotch: true), 185)
        XCTAssertEqual(IslandMetrics.estimatedNotchWidth(screenWidth: 1728, hasNotch: false), 0)
    }
}
