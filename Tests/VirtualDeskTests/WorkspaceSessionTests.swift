import AppKit
import XCTest
@testable import VirtualDesk

final class WorkspaceSessionTests: XCTestCase {
    func testStartWorkspaceAfterDisplayOnlySessionDoesNotCreateSecondDisplay() throws {
        let provisioner = FakeVirtualDisplayProvisioner(displayID: 42)
        let displayService = FakeDisplayService(displays: [
            ManagedDisplay(
                id: 42,
                name: "VirtualDesk Virtual Display",
                frame: CGRect(x: 4000, y: 0, width: 1440, height: 900),
                visibleFrame: CGRect(x: 4000, y: 0, width: 1440, height: 900)
            )
        ])
        let session = WorkspaceSession(
            configuration: .pocDefault,
            virtualDisplayProvisioner: provisioner,
            displayService: displayService,
            appService: ThrowingAppService(),
            accessibilityService: ThrowingAccessibilityService()
        )

        let displayOnlyStatus = try session.startDisplay(params: nil)
        let workspaceStatus = try session.start(params: StartWorkspaceParams(
            appPath: "/Applications/Example.app",
            width: nil,
            height: nil,
            refreshRate: nil,
            hiDPI: nil,
            profile: nil
        ))

        XCTAssertEqual(provisioner.createCallCount, 1)
        XCTAssertEqual(displayOnlyStatus.display?.id, 42)
        XCTAssertEqual(workspaceStatus.display?.id, 42)
        XCTAssertEqual(workspaceStatus.targetApp.path, "/Applications/Example.app")
    }

    func testWindowGuardianLaunchesMissingAppAtMostThreeTimes() {
        let appService = LaunchCountingAppService()
        let guardian = WindowGuardian(
            configuration: .pocDefault,
            displayService: FakeDisplayService(displays: [
                ManagedDisplay(
                    id: 42,
                    name: "VirtualDesk Virtual Display",
                    frame: CGRect(x: 4000, y: 0, width: 1440, height: 900),
                    visibleFrame: CGRect(x: 4000, y: 0, width: 1440, height: 900)
                )
            ]),
            appService: appService,
            accessibilityService: ThrowingAccessibilityService()
        )

        for _ in 0..<5 {
            guardian.enforceOnce()
        }

        XCTAssertEqual(appService.launchCallCount, 3)
    }
}

private final class FakeVirtualDisplayLease: VirtualDisplayLeasing {
    let displayID: CGDirectDisplayID

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
    }
}

private final class FakeVirtualDisplayProvisioner: VirtualDisplayProvisioning {
    private let displayID: CGDirectDisplayID
    private(set) var createCallCount = 0

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
    }

    func createDisplay(spec: VirtualDisplaySpec) throws -> VirtualDisplayLeasing {
        createCallCount += 1
        return FakeVirtualDisplayLease(displayID: displayID)
    }
}

private final class FakeDisplayService: DisplayServicing {
    private let displays: [ManagedDisplay]

    init(displays: [ManagedDisplay]) {
        self.displays = displays
    }

    func availableDisplays() -> [ManagedDisplay] {
        displays
    }
}

private final class ThrowingAppService: AppServicing {
    func launchOrActivateApp(at path: String) throws -> NSRunningApplication {
        throw VirtualDeskError.appNotFound(path)
    }

    func runningApp(at path: String) -> NSRunningApplication? {
        nil
    }

    func listRunnableApps() -> [AppSnapshot] {
        []
    }
}

private final class LaunchCountingAppService: AppServicing {
    private(set) var launchCallCount = 0

    func launchOrActivateApp(at path: String) throws -> NSRunningApplication {
        launchCallCount += 1
        throw VirtualDeskError.appNotFound(path)
    }

    func runningApp(at path: String) -> NSRunningApplication? {
        nil
    }

    func listRunnableApps() -> [AppSnapshot] {
        []
    }
}

private final class ThrowingAccessibilityService: AccessibilityServicing {
    func isTrusted(prompt: Bool) -> Bool {
        true
    }

    func primaryWindow(for app: NSRunningApplication) throws -> ManagedWindow {
        throw VirtualDeskError.windowNotFound("test")
    }

    func move(window: ManagedWindow, to frame: CGRect) throws {}

    func frame(of window: ManagedWindow) throws -> CGRect {
        .zero
    }
}
