import CoreGraphics
import Foundation

struct AgentStatus: Codable {
    let state: WorkspaceState
    let pid: Int32
    let display: DisplaySnapshot?
    let targetApp: TargetAppSnapshot
    let window: WindowSnapshot?
    let guardStatus: GuardSnapshot
    let message: String?

    static func stopped(configuration: VirtualDeskConfiguration, message: String? = nil) -> AgentStatus {
        AgentStatus(
            state: .stopped,
            pid: 0,
            display: nil,
            targetApp: TargetAppSnapshot(path: configuration.targetAppPath, bundleID: nil),
            window: nil,
            guardStatus: GuardSnapshot(enabled: false, intervalMS: Int(configuration.guardianInterval * 1000)),
            message: message
        )
    }

    static func runningUnknown(
        configuration: VirtualDeskConfiguration,
        pid: Int32,
        message: String
    ) -> AgentStatus {
        AgentStatus(
            state: .running,
            pid: pid,
            display: nil,
            targetApp: TargetAppSnapshot(path: configuration.targetAppPath, bundleID: nil),
            window: nil,
            guardStatus: GuardSnapshot(enabled: true, intervalMS: Int(configuration.guardianInterval * 1000)),
            message: message
        )
    }
}

enum WorkspaceState: String, Codable {
    case stopped
    case starting
    case running
    case stopping
    case failed
}

struct DisplaySnapshot: Codable {
    let id: UInt32
    let name: String
    let frame: RectSnapshot
    let visibleFrame: RectSnapshot
    let isVirtual: Bool

    init(display: ManagedDisplay, virtualDisplayID: CGDirectDisplayID?) {
        id = display.id
        name = display.name
        frame = RectSnapshot(rect: display.frame)
        visibleFrame = RectSnapshot(rect: display.visibleFrame)
        isVirtual = virtualDisplayID == display.id || display.name.localizedCaseInsensitiveContains("virtual")
    }
}

struct TargetAppSnapshot: Codable {
    let path: String
    let bundleID: String?
}

struct WindowSnapshot: Codable {
    let pid: Int32
    let rect: RectSnapshot
}

struct GuardSnapshot: Codable {
    let enabled: Bool
    let intervalMS: Int
}

struct RectSnapshot: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
    }
}
