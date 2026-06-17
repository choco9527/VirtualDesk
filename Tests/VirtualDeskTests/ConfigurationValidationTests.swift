import XCTest
@testable import VirtualDesk

final class ConfigurationValidationTests: XCTestCase {
    func testResolvesFromDefaultProfile() throws {
        let configuration = try VirtualDeskConfiguration.resolved(
            base: .pocDefault,
            config: nil,
            params: StartWorkspaceParams(
                appPath: "/Applications/Codex.app",
                width: 1440,
                height: 900,
                refreshRate: 60,
                hiDPI: true,
                profile: "codex_mobile_1440x900"
            )
        )

        XCTAssertEqual(configuration.targetAppPath, "/Applications/Codex.app")
        XCTAssertEqual(configuration.virtualDisplayWidth, 1440)
        XCTAssertEqual(configuration.virtualDisplayHeight, 900)
        XCTAssertEqual(configuration.virtualDisplayRefreshRate, 60)
        XCTAssertEqual(configuration.virtualDisplayHiDPI, true)
    }

    func testRejectsUnsupportedRefreshRate() {
        XCTAssertThrowsError(
            try VirtualDeskConfiguration.resolved(
                base: .pocDefault,
                config: nil,
                params: StartWorkspaceParams(
                    appPath: "/Applications/Codex.app",
                    width: 1440,
                    height: 900,
                    refreshRate: 59,
                    hiDPI: true,
                    profile: nil
                )
            )
        ) { error in
            XCTAssertEqual((error as? VirtualDeskError)?.code, "INVALID_PARAMS")
        }
    }
}
