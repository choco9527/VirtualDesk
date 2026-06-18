import XCTest
@testable import VirtualDesk

final class AgentPresentationPolicyTests: XCTestCase {
    func testAgentCommandRunsHeadless() {
        XCTAssertTrue(AgentPresentationPolicy.shouldRunHeadless(arguments: ["VirtualDesk", "agent"]))
    }

    func testInteractiveCommandsKeepDefaultPresentation() {
        XCTAssertFalse(AgentPresentationPolicy.shouldRunHeadless(arguments: ["VirtualDesk"]))
        XCTAssertFalse(AgentPresentationPolicy.shouldRunHeadless(arguments: ["VirtualDesk", "list-apps"]))
        XCTAssertFalse(AgentPresentationPolicy.shouldRunHeadless(arguments: ["VirtualDesk", "create-screen"]))
    }
}
