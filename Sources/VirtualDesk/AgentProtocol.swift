import Foundation

struct BasicCommandRequest: Decodable {
    let id: String
    let method: AgentMethod
}

struct CommandRequest<Params: Decodable>: Decodable {
    let id: String
    let method: AgentMethod
    let params: Params?
}

enum AgentMethod: String, Codable {
    case status
    case accessibilityStatus = "accessibility_status"
    case requestAccessibility = "request_accessibility"
    case listDisplays = "list_displays"
    case startWorkspace = "start_workspace"
    case stopWorkspace = "stop_workspace"
}

struct EmptyParams: Codable {}

struct StartWorkspaceParams: Codable {
    let appPath: String?
    let width: UInt32?
    let height: UInt32?
    let refreshRate: Double?
}

struct CommandResponse<Result: Encodable>: Encodable {
    let id: String
    let ok: Bool
    let result: Result?
    let error: String?

    static func success(id: String, result: Result) -> CommandResponse<Result> {
        CommandResponse(id: id, ok: true, result: result, error: nil)
    }

    static func failure(id: String, error: String) -> CommandResponse<Result> {
        CommandResponse(id: id, ok: false, result: nil, error: error)
    }
}

struct AgentEvent<Data: Encodable>: Encodable {
    let event: String
    let data: Data
}

struct MessageResult: Codable {
    let message: String
}

struct DisplayListResult: Codable {
    let displays: [DisplaySnapshot]
}

struct AccessibilityResult: Codable {
    let trusted: Bool
    let promptShown: Bool
    let message: String?
}
