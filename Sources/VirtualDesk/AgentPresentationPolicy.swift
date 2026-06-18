import AppKit
import Foundation

enum AgentPresentationPolicy {
    static func shouldRunHeadless(arguments: [String]) -> Bool {
        let command = arguments.dropFirst().first
        return command == "agent"
    }

    static func applyIfNeeded(arguments: [String]) {
        guard shouldRunHeadless(arguments: arguments) else {
            return
        }

        NSApplication.shared.setActivationPolicy(.prohibited)
    }
}
