import CoreGraphics
import XCTest
@testable import VirtualDesk

final class FramePolicyTests: XCTestCase {
    func testDoesNotMoveWhenWindowStaysInsideTargetDisplay() {
        let windowFrame = CGRect(x: 120, y: 80, width: 1200, height: 800)
        let targetFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        XCTAssertFalse(FramePolicy.shouldMove(windowFrame: windowFrame, targetFrame: targetFrame))
    }

    func testMovesWhenWindowEscapesTargetDisplay() {
        let windowFrame = CGRect(x: 2000, y: 0, width: 1920, height: 1080)
        let targetFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        XCTAssertTrue(FramePolicy.shouldMove(windowFrame: windowFrame, targetFrame: targetFrame))
    }

    func testMovesWhenWindowBottomEdgeEscapesTargetDisplay() {
        let windowFrame = CGRect(x: 0, y: 400, width: 1200, height: 800)
        let targetFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        XCTAssertTrue(FramePolicy.shouldMove(windowFrame: windowFrame, targetFrame: targetFrame))
    }
}
