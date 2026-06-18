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
                captureScreen: true
            )
        )

        XCTAssertEqual(result.platform, "macos")
        XCTAssertEqual(result.protocolVersion, "1.0")
        XCTAssertTrue(result.supports.virtualDisplay)
        XCTAssertTrue(result.supports.windowControl)
        XCTAssertTrue(result.supports.stopWorkspace)
        XCTAssertTrue(result.supports.listApps)
        XCTAssertTrue(result.supports.captureScreen)
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
}
