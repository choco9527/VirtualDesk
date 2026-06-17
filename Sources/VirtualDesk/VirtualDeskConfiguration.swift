import Foundation

struct VirtualDeskConfiguration {
    let targetAppPath: String
    let targetDisplayKeywords: [String]
    let virtualDisplayName: String
    let virtualDisplayWidth: UInt32
    let virtualDisplayHeight: UInt32
    let virtualDisplayRefreshRate: Double
    let guardianInterval: TimeInterval

    static let pocDefault = VirtualDeskConfiguration(
        targetAppPath: "/Applications/Codex.app",
        targetDisplayKeywords: ["VirtualDesk", "BetterDisplay", "Virtual"],
        virtualDisplayName: "VirtualDesk Virtual Display",
        virtualDisplayWidth: 1440,
        virtualDisplayHeight: 900,
        virtualDisplayRefreshRate: 60,
        guardianInterval: 1
    )

    func overriding(_ params: StartWorkspaceParams?) -> VirtualDeskConfiguration {
        VirtualDeskConfiguration(
            targetAppPath: params?.appPath ?? targetAppPath,
            targetDisplayKeywords: targetDisplayKeywords,
            virtualDisplayName: virtualDisplayName,
            virtualDisplayWidth: params?.width ?? virtualDisplayWidth,
            virtualDisplayHeight: params?.height ?? virtualDisplayHeight,
            virtualDisplayRefreshRate: params?.refreshRate ?? virtualDisplayRefreshRate,
            guardianInterval: guardianInterval
        )
    }
}
