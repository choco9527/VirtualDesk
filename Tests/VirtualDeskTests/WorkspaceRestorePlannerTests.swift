import XCTest
@testable import VirtualDesk

final class WorkspaceRestorePlannerTests: XCTestCase {
    func testReturnsEmptyWhenDisplayOnlySessionNeverPinnedAnyApp() {
        XCTAssertEqual(WorkspaceRestorePlanner.pathsToRestore(pinnedAppPaths: []), [])
    }

    func testReturnsPinnedAppsInOrderForWorkspaceCleanup() {
        let paths = [
            "/Applications/Codex.app",
            "/Applications/Google Chrome.app",
        ]

        XCTAssertEqual(WorkspaceRestorePlanner.pathsToRestore(pinnedAppPaths: paths), paths)
    }
}
