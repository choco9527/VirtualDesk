import XCTest
@testable import VirtualDesk

final class ProtocolShapeTests: XCTestCase {
    func testErrorPayloadEncodesAsStructuredObject() throws {
        let response = CommandResponse<MessageResult>.failure(
            id: "1",
            error: VirtualDeskError.accessibilityPermissionMissing.payload
        )

        let data = try JSONEncoder.virtualDeskLine.encode(response)
        let output = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(output.contains("\"error\""))
        XCTAssertTrue(output.contains("\"code\":\"ACCESSIBILITY_PERMISSION_MISSING\""))
        XCTAssertTrue(output.contains("\"message\""))
    }

    func testCapabilitiesShape() {
        let result = CapabilitiesResult(
            platform: "macos",
            protocolVersion: "1.0",
            supports: AgentSupportFlags(
                virtualDisplay: true,
                windowControl: true,
                stopWorkspace: true,
                listApps: true,
                captureScreen: true,
                startDisplay: true
            )
        )

        XCTAssertEqual(result.platform, "macos")
        XCTAssertEqual(result.protocolVersion, "1.0")
        XCTAssertTrue(result.supports.virtualDisplay)
        XCTAssertTrue(result.supports.windowControl)
        XCTAssertTrue(result.supports.stopWorkspace)
        XCTAssertTrue(result.supports.listApps)
        XCTAssertTrue(result.supports.captureScreen)
        XCTAssertTrue(result.supports.startDisplay)
    }

    func testAccessibilityResultUsesSnakeCaseKeys() throws {
        let result = AccessibilityResult(
            trusted: false,
            promptShown: true,
            message: "permission required"
        )

        let data = try JSONEncoder.virtualDeskLine.encode(result)
        let output = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(output.contains("\"prompt_shown\":true"))
    }

    func testAppSnapshotIncludesIconKey() throws {
        let snapshot = AppSnapshot(
            name: "Codex",
            bundleID: "com.openai.codex",
            appPath: "/Applications/Codex.app",
            pid: 1,
            isRunning: true,
            iconPNGBase64: "abc"
        )

        let data = try JSONEncoder.virtualDeskLine.encode(snapshot)
        let output = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(output.contains("\"icon_png_base64\":\"abc\""))
        XCTAssertTrue(output.contains("\"is_running\":true"))
    }

    func testStartWorkspaceParamsDecodeSnakeCaseRequest() throws {
        let data = Data("""
        {"id":"1","method":"start_workspace","params":{"app_path":"/System/Applications/Calculator.app","refresh_rate":60,"hidpi":true}}
        """.utf8)

        let request = try JSONDecoder.virtualDeskProtocol.decode(
            CommandRequest<StartWorkspaceParams>.self,
            from: data
        )

        XCTAssertEqual(request.params?.appPath, "/System/Applications/Calculator.app")
        XCTAssertEqual(request.params?.refreshRate, 60)
        XCTAssertEqual(request.params?.hiDPI, true)
    }
}
