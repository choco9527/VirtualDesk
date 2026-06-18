import Foundation

enum VirtualDeskError: LocalizedError {
    case accessibilityPermissionMissing
    case agentAlreadyRunning(String)
    case appNotFound(String)
    case targetDisplayNotFound([String])
    case appLaunchFailed(String)
    case appNotRunning(String)
    case jsonEncodingFailed
    case invalidParams(String)
    case lockUnavailable(String)
    case invalidCommand(String)
    case internalError(String)
    case screenCapturePermissionMissing
    case screenCaptureUnavailable(String)
    case virtualDisplayCreateFailed(String)
    case virtualDisplayNotReady(UInt32)
    case workspaceAlreadyRunning
    case workspaceNotRunning
    case windowNotFound(String)
    case windowMoveFailed(String)

    var code: String {
        switch self {
        case .accessibilityPermissionMissing:
            return "ACCESSIBILITY_PERMISSION_MISSING"
        case .agentAlreadyRunning:
            return "AGENT_ALREADY_RUNNING"
        case .appNotFound:
            return "APP_NOT_FOUND"
        case .targetDisplayNotFound, .invalidParams:
            return "INVALID_PARAMS"
        case .appLaunchFailed, .appNotRunning:
            return "APP_NOT_RUNNING"
        case .jsonEncodingFailed, .lockUnavailable, .invalidCommand, .internalError:
            return "INTERNAL_ERROR"
        case .screenCapturePermissionMissing:
            return "SCREEN_CAPTURE_PERMISSION_MISSING"
        case .screenCaptureUnavailable:
            return "SCREEN_CAPTURE_UNAVAILABLE"
        case .virtualDisplayCreateFailed:
            return "VIRTUAL_DISPLAY_CREATE_FAILED"
        case .virtualDisplayNotReady:
            return "VIRTUAL_DISPLAY_NOT_READY"
        case .workspaceAlreadyRunning:
            return "WORKSPACE_ALREADY_RUNNING"
        case .workspaceNotRunning:
            return "WORKSPACE_NOT_RUNNING"
        case .windowNotFound:
            return "WINDOW_NOT_FOUND"
        case .windowMoveFailed:
            return "WINDOW_MOVE_FAILED"
        }
    }

    var payload: AgentErrorPayload {
        AgentErrorPayload(code: code, message: errorDescription ?? "Unknown error.")
    }

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            return "Accessibility permission is required. Enable it in System Settings > Privacy & Security > Accessibility."
        case let .agentAlreadyRunning(path):
            return "VirtualDesk is already running. lock=\(path)"
        case let .appNotFound(path):
            return "App path does not exist or is not an app bundle: \(path)."
        case let .targetDisplayNotFound(keywords):
            return "Target display not found. Expected display name containing one of: \(keywords.joined(separator: ", "))."
        case let .appLaunchFailed(path):
            return "Failed to launch app at \(path)."
        case let .appNotRunning(path):
            return "App is not running: \(path)."
        case .jsonEncodingFailed:
            return "Failed to encode JSON output."
        case let .invalidParams(reason):
            return "Invalid params: \(reason)"
        case let .lockUnavailable(reason):
            return reason
        case let .invalidCommand(reason):
            return "Invalid command: \(reason)"
        case let .internalError(reason):
            return reason
        case .screenCapturePermissionMissing:
            return "Screen Recording permission is required to preview the virtual display."
        case let .screenCaptureUnavailable(reason):
            return "Screen capture unavailable: \(reason)"
        case let .virtualDisplayCreateFailed(reason):
            return "Failed to create virtual display: \(reason)."
        case let .virtualDisplayNotReady(displayID):
            return "Virtual display was created but not visible to NSScreen yet. displayID=\(displayID)."
        case .workspaceAlreadyRunning:
            return "Workspace is already running."
        case .workspaceNotRunning:
            return "Workspace is not running."
        case let .windowNotFound(appName):
            return "No controllable main window found for \(appName)."
        case let .windowMoveFailed(reason):
            return "Failed to move window: \(reason)."
        }
    }
}
