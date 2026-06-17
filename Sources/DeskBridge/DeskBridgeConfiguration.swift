import Foundation

struct DeskBridgeConfiguration {
    let targetAppPath: String
    let targetDisplayKeywords: [String]
    let virtualDisplayName: String
    let virtualDisplayWidth: UInt32
    let virtualDisplayHeight: UInt32
    let virtualDisplayRefreshRate: Double
    let guardianInterval: TimeInterval

    static let pocDefault = DeskBridgeConfiguration(
        targetAppPath: "/Applications/Codex.app",
        targetDisplayKeywords: ["DeskBridge", "BetterDisplay", "Virtual"],
        virtualDisplayName: "DeskBridge Virtual Display",
        virtualDisplayWidth: 1440,
        virtualDisplayHeight: 900,
        virtualDisplayRefreshRate: 60,
        guardianInterval: 1
    )
}
