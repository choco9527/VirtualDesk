import Foundation

enum DeskBridgeError: LocalizedError {
    case accessibilityPermissionMissing
    case agentAlreadyRunning(String)
    case targetDisplayNotFound([String])
    case appLaunchFailed(String)
    case appNotRunning(String)
    case jsonEncodingFailed
    case lockUnavailable(String)
    case virtualDisplayCreateFailed(String)
    case virtualDisplayNotReady(UInt32)
    case windowNotFound(String)
    case windowMoveFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            return "Accessibility permission is required. Enable it in System Settings > Privacy & Security > Accessibility."
        case let .agentAlreadyRunning(path):
            return "DeskBridge is already running. lock=\(path)"
        case let .targetDisplayNotFound(keywords):
            return "Target display not found. Expected display name containing one of: \(keywords.joined(separator: ", "))."
        case let .appLaunchFailed(path):
            return "Failed to launch app at \(path)."
        case let .appNotRunning(path):
            return "App is not running: \(path)."
        case .jsonEncodingFailed:
            return "Failed to encode JSON output."
        case let .lockUnavailable(reason):
            return reason
        case let .virtualDisplayCreateFailed(reason):
            return "Failed to create virtual display: \(reason)."
        case let .virtualDisplayNotReady(displayID):
            return "Virtual display was created but not visible to NSScreen yet. displayID=\(displayID)."
        case let .windowNotFound(appName):
            return "No controllable main window found for \(appName)."
        case let .windowMoveFailed(reason):
            return "Failed to move window: \(reason)."
        }
    }
}
