import CoreGraphics
import XCTest
@testable import VirtualDesk

final class DisplayArrangementTests: XCTestCase {
    func testPlacesVirtualDisplayToTheRightOfPhysicalDisplays() {
        let plan = DisplayArrangement.placementPlan(
            displays: [
                DisplayLayoutItem(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900)),
                DisplayLayoutItem(id: 2, frame: CGRect(x: 1440, y: -280, width: 2560, height: 1440)),
                DisplayLayoutItem(id: 78, frame: CGRect(x: 0, y: 0, width: 390, height: 844)),
            ],
            virtualDisplayID: 78,
            anchorDisplayID: 1
        )

        XCTAssertEqual(
            plan,
            [
                DisplayPlacement(id: 1, x: 0, y: 0),
                DisplayPlacement(id: 2, x: 1440, y: -280),
                DisplayPlacement(id: 78, x: 4080, y: 0),
            ]
        )
    }
}
