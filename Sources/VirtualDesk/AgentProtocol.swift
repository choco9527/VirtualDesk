import Foundation

struct BasicCommandRequest: Codable {
    let id: String
    let method: AgentMethod
}

struct CommandRequest<Params: Codable>: Codable {
    let id: String
    let method: AgentMethod
    let params: Params?
}

enum AgentMethod: String, Codable {
    case capabilities
    case status
    case accessibilityStatus = "accessibility_status"
    case requestAccessibility = "request_accessibility"
    case listDisplays = "list_displays"
    case listApps = "list_apps"
    case startWorkspace = "start_workspace"
    case stopWorkspace = "stop_workspace"
}

struct EmptyParams: Codable {}

struct StartWorkspaceParams: Codable {
    let appPath: String?
    let width: UInt32?
    let height: UInt32?
    let refreshRate: Double?
    let hiDPI: Bool?
    let profile: String?

    enum CodingKeys: String, CodingKey {
        case appPath = "app_path"
        case width
        case height
        case refreshRate = "refresh_rate"
        case hiDPI = "hidpi"
        case profile
    }
}

struct CommandResponse<Result: Codable>: Codable {
    let id: String
    let ok: Bool
    let result: Result?
    let error: AgentErrorPayload?

    static func success(id: String, result: Result) -> CommandResponse<Result> {
        CommandResponse(id: id, ok: true, result: result, error: nil)
    }

    static func failure(id: String, error: AgentErrorPayload) -> CommandResponse<Result> {
        CommandResponse(id: id, ok: false, result: nil, error: error)
    }
}

struct AgentEvent<Data: Codable>: Codable {
    let event: String
    let data: Data
}

struct AgentErrorPayload: Codable, Equatable {
    let code: String
    let message: String
}

struct CapabilitiesResult: Codable {
    let platform: String
    let protocolVersion: String
    let supports: AgentSupportFlags
}

struct AgentSupportFlags: Codable {
    let virtualDisplay: Bool
    let windowControl: Bool
    let stopWorkspace: Bool
    let listApps: Bool
}

struct MessageResult: Codable {
    let message: String
}

struct DisplayListResult: Codable {
    let displays: [DisplaySnapshot]
}

struct AppListResult: Codable {
    let apps: [AppSnapshot]
}

struct AppSnapshot: Codable, Equatable {
    let name: String
    let bundleID: String?
    let appPath: String
    let pid: Int32

    enum CodingKeys: String, CodingKey {
        case name
        case bundleID = "bundle_id"
        case appPath = "app_path"
        case pid
    }
}

struct AccessibilityResult: Codable {
    let trusted: Bool
    let promptShown: Bool
    let message: String?
}
