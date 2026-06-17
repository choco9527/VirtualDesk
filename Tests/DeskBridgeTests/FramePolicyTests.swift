import CoreGraphics
import XCTest
@testable import DeskBridge

final class FramePolicyTests: XCTestCase {
    func testDoesNotMoveWhenFrameMatchesWithinTolerance() {
        let windowFrame = CGRect(x: 2, y: 2, width: 1918, height: 1078)
        let targetFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        XCTAssertFalse(FramePolicy.shouldMove(windowFrame: windowFrame, targetFrame: targetFrame))
    }

    func testMovesWhenWindowEscapesTargetDisplay() {
        let windowFrame = CGRect(x: 2000, y: 0, width: 1920, height: 1080)
        let targetFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        XCTAssertTrue(FramePolicy.shouldMove(windowFrame: windowFrame, targetFrame: targetFrame))
    }

    func testMovesWhenSizeDiffersBeyondTolerance() {
        let windowFrame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let targetFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        XCTAssertTrue(FramePolicy.shouldMove(windowFrame: windowFrame, targetFrame: targetFrame))
    }
}
