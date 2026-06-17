import AppKit
import Foundation

protocol AppServicing {
    func launchOrActivateApp(at path: String) throws -> NSRunningApplication
    func runningApp(at path: String) -> NSRunningApplication?
}

final class MacAppService: AppServicing {
    func launchOrActivateApp(at path: String) throws -> NSRunningApplication {
        if let app = runningApp(at: path) {
            app.activate(options: [.activateIgnoringOtherApps])
            return app
        }

        let url = URL(fileURLWithPath: path)
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

        throw launchError ?? DeskBridgeError.appLaunchFailed(url.path)
    }
}
