import AppKit
import Foundation

protocol AppServicing {
    func launchOrActivateApp(at path: String) throws -> NSRunningApplication
    func runningApp(at path: String) -> NSRunningApplication?
    func listRunnableApps() -> [AppSnapshot]
}

enum AppBundlePolicy {
    static func isSupportedAppBundle(url: URL) -> Bool {
        guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
            return false
        }

        return !isChromeWebAppBundle(url: url)
            && !isScriptAppletBundle(url: url)
    }

    static func isChromeWebAppBundle(url: URL) -> Bool {
        guard let bundle = Bundle(url: url) else {
            return false
        }

        let hasShortcutURL = bundle.object(forInfoDictionaryKey: "CrAppModeShortcutURL") != nil
        let hostBundleID = bundle.object(forInfoDictionaryKey: "CrBundleIdentifier") as? String
        return hasShortcutURL || hostBundleID == "com.google.Chrome"
    }

    static func isScriptAppletBundle(url: URL) -> Bool {
        guard let bundle = Bundle(url: url) else {
            return false
        }

        let executable = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
        let signature = bundle.object(forInfoDictionaryKey: "CFBundleSignature") as? String
        let requiresCarbon = bundle.object(forInfoDictionaryKey: "LSRequiresCarbon") as? Bool
        let isOSAApplet = bundle.object(forInfoDictionaryKey: "OSAAppletShowStartupScreen") != nil

        return signature == "aplt"
            || isOSAApplet
            || (executable == "applet" && requiresCarbon == true)
    }
}

final class MacAppService: AppServicing {
    func launchOrActivateApp(at path: String) throws -> NSRunningApplication {
        let url = URL(fileURLWithPath: path)
        guard AppBundlePolicy.isSupportedAppBundle(url: url) else {
            throw VirtualDeskError.invalidParams("Unsupported app bundle: \(path).")
        }

        if let app = runningApp(at: path) {
            app.activate(options: [.activateIgnoringOtherApps])
            return app
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        return try runLaunch(url: url, configuration: configuration)
    }

    func runningApp(at path: String) -> NSRunningApplication? {
        let targetURL = URL(fileURLWithPath: path).standardizedFileURL

        return NSWorkspace.shared.runningApplications.first { app in
            app.bundleURL?.standardizedFileURL == targetURL
        }
    }

    func listRunnableApps() -> [AppSnapshot] {
        let runningByPath = AppSnapshotIndex.byPath(runningAppSnapshots())

        let installed = installedAppURLs().compactMap { url -> AppSnapshot? in
            let appPath = url.standardizedFileURL.path
            if let running = runningByPath[appPath] {
                return running
            }
            return installedAppSnapshot(url: url)
        }

        return installed
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func runLaunch(
        url: URL,
        configuration: NSWorkspace.OpenConfiguration
    ) throws -> NSRunningApplication {
        var launchedApp: NSRunningApplication?
        var launchError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            launchedApp = app
            launchError = error
            semaphore.signal()
        }

        semaphore.wait()

        if let launchedApp {
            return launchedApp
        }

        throw launchError ?? VirtualDeskError.appLaunchFailed(url.path)
    }

    private func runningAppSnapshots() -> [AppSnapshot] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard !app.isTerminated,
                  !app.isHidden,
                  app.activationPolicy == .regular,
                  let appURL = app.bundleURL?.standardizedFileURL,
                  AppBundlePolicy.isSupportedAppBundle(url: appURL) else {
                return nil
            }
            let appPath = appURL.path

            return AppSnapshot(
                name: app.localizedName ?? app.bundleIdentifier ?? appPath,
                bundleID: app.bundleIdentifier,
                appPath: appPath,
                pid: app.processIdentifier,
                isRunning: true,
                iconPNGBase64: app.icon.flatMap(iconBase64)
            )
        }
    }

    private func installedAppURLs(fileManager: FileManager = .default) -> [URL] {
        let searchRoots = [
            "/Applications",
            "\(NSHomeDirectory())/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/Applications/Utilities",
        ]

        let urls = searchRoots.flatMap { root in
            appBundleURLs(root: URL(fileURLWithPath: root), fileManager: fileManager)
        }
        return Array(Set(urls.map(\.standardizedFileURL)))
    }

    private func appBundleURLs(root: URL, fileManager: FileManager) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isApplicationKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  url.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
                return nil
            }
            enumerator.skipDescendants()
            return url
        }
    }

    private func installedAppSnapshot(url: URL) -> AppSnapshot? {
        guard AppBundlePolicy.isSupportedAppBundle(url: url) else {
            return nil
        }

        guard let bundle = Bundle(url: url) else {
            return nil
        }

        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent

        return AppSnapshot(
            name: name,
            bundleID: bundle.bundleIdentifier,
            appPath: url.standardizedFileURL.path,
            pid: 0,
            isRunning: false,
            iconPNGBase64: iconBase64(NSWorkspace.shared.icon(forFile: url.path))
        )
    }

    private func iconBase64(_ image: NSImage) -> String? {
        let resizedImage = NSImage(size: CGSize(width: 64, height: 64))
        resizedImage.lockFocus()
        image.draw(
            in: NSRect(x: 0, y: 0, width: 64, height: 64),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        resizedImage.unlockFocus()

        guard let tiffData = resizedImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        return pngData.base64EncodedString()
    }
}

enum AppSnapshotIndex {
    static func byPath(_ apps: [AppSnapshot]) -> [String: AppSnapshot] {
        apps.reduce(into: [:]) { result, app in
            if result[app.appPath] == nil {
                result[app.appPath] = app
            }
        }
    }
}
