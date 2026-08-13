import XCTest
@testable import zTools

final class ScreenCoordinateTests: XCTestCase {
    func testConvertRoundTrip() {
        let cocoa = CGRect(x: 100, y: 200, width: 300, height: 150)
        let cg = ScreenCoordinate.convertCocoaRectToCG(cocoa)
        let back = ScreenCoordinate.convertCGRectToCocoa(cg)

        XCTAssertEqual(back.origin.x, cocoa.origin.x, accuracy: 0.001)
        XCTAssertEqual(back.origin.y, cocoa.origin.y, accuracy: 0.001)
        XCTAssertEqual(back.size.width, cocoa.size.width, accuracy: 0.001)
        XCTAssertEqual(back.size.height, cocoa.size.height, accuracy: 0.001)
    }

    func testConvertIgnoresZeroRect() {
        let zero = CGRect.zero
        let cg = ScreenCoordinate.convertCocoaRectToCG(zero)
        XCTAssertEqual(cg.width, 0, accuracy: 0.001)
        XCTAssertEqual(cg.height, 0, accuracy: 0.001)
    }
}
