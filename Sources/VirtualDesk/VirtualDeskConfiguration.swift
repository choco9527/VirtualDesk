import Foundation

struct VirtualDeskProfile: Codable, Equatable {
    let name: String
    let appPath: String
    let width: UInt32
    let height: UInt32
    let refreshRate: Double
    let hiDPI: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case appPath = "app_path"
        case width
        case height
        case refreshRate = "refresh_rate"
        case hiDPI = "hidpi"
    }
}

struct VirtualDeskUserConfig: Codable, Equatable {
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

struct VirtualDeskConfiguration {
    let targetAppPath: String
    let targetDisplayKeywords: [String]
    let virtualDisplayName: String
    let virtualDisplayWidth: UInt32
    let virtualDisplayHeight: UInt32
    let virtualDisplayRefreshRate: Double
    let virtualDisplayHiDPI: Bool
    let guardianInterval: TimeInterval

    static let defaultProfileName = "codex_mobile_1440x900"
    static let defaultProfiles = [
        defaultProfileName: VirtualDeskProfile(
            name: defaultProfileName,
            appPath: "/Applications/Codex.app",
            width: 1440,
            height: 900,
            refreshRate: 60,
            hiDPI: true
        )
    ]
    static let allowedRefreshRates: Set<Double> = [30, 60, 120]
    static let minWidth: UInt32 = 640
    static let maxWidth: UInt32 = 7680
    static let minHeight: UInt32 = 480
    static let maxHeight: UInt32 = 4320

    static let pocDefault = VirtualDeskConfiguration(
        targetAppPath: "/Applications/Codex.app",
        targetDisplayKeywords: ["VirtualDesk", "BetterDisplay", "Virtual"],
        virtualDisplayName: "VirtualDesk Virtual Display",
        virtualDisplayWidth: 1440,
        virtualDisplayHeight: 900,
        virtualDisplayRefreshRate: 60,
        virtualDisplayHiDPI: true,
        guardianInterval: 1
    )

    static func resolved(
        base: VirtualDeskConfiguration = .pocDefault,
        config: VirtualDeskUserConfig?,
        params: StartWorkspaceParams?
    ) throws -> VirtualDeskConfiguration {
        let profileName = params?.profile ?? config?.profile ?? defaultProfileName
        guard let profile = defaultProfiles[profileName] else {
            throw VirtualDeskError.invalidParams("Unknown profile: \(profileName).")
        }

        let appPath = params?.appPath ?? config?.appPath ?? profile.appPath
        let width = params?.width ?? config?.width ?? profile.width
        let height = params?.height ?? config?.height ?? profile.height
        let refreshRate = params?.refreshRate ?? config?.refreshRate ?? profile.refreshRate
        let hiDPI = params?.hiDPI ?? config?.hiDPI ?? profile.hiDPI

        let resolved = VirtualDeskConfiguration(
            targetAppPath: appPath,
            targetDisplayKeywords: base.targetDisplayKeywords,
            virtualDisplayName: base.virtualDisplayName,
            virtualDisplayWidth: width,
            virtualDisplayHeight: height,
            virtualDisplayRefreshRate: refreshRate,
            virtualDisplayHiDPI: hiDPI,
            guardianInterval: base.guardianInterval
        )

        try resolved.validate()
        return resolved
    }

    func validate(fileManager: FileManager = .default) throws {
        let standardizedPath = URL(fileURLWithPath: targetAppPath).standardizedFileURL.path
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardizedPath, isDirectory: &isDirectory),
              isDirectory.boolValue,
              standardizedPath.lowercased().hasSuffix(".app") else {
            throw VirtualDeskError.appNotFound(targetAppPath)
        }

        guard Self.minWidth...Self.maxWidth ~= virtualDisplayWidth else {
            throw VirtualDeskError.invalidParams(
                "width must be between \(Self.minWidth) and \(Self.maxWidth)."
            )
        }

        guard Self.minHeight...Self.maxHeight ~= virtualDisplayHeight else {
            throw VirtualDeskError.invalidParams(
                "height must be between \(Self.minHeight) and \(Self.maxHeight)."
            )
        }

        guard Self.allowedRefreshRates.contains(virtualDisplayRefreshRate) else {
            let values = Self.allowedRefreshRates.sorted().map { String(Int($0)) }.joined(separator: ", ")
            throw VirtualDeskError.invalidParams("refresh_rate must be one of: \(values).")
        }
    }

    func overriding(_ params: StartWorkspaceParams?) -> VirtualDeskConfiguration {
        VirtualDeskConfiguration(
            targetAppPath: params?.appPath ?? targetAppPath,
            targetDisplayKeywords: targetDisplayKeywords,
            virtualDisplayName: virtualDisplayName,
            virtualDisplayWidth: params?.width ?? virtualDisplayWidth,
            virtualDisplayHeight: params?.height ?? virtualDisplayHeight,
            virtualDisplayRefreshRate: params?.refreshRate ?? virtualDisplayRefreshRate,
            virtualDisplayHiDPI: params?.hiDPI ?? virtualDisplayHiDPI,
            guardianInterval: guardianInterval
        )
    }
}
