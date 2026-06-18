import XCTest
@testable import VirtualDesk

final class AppBundlePolicyTests: XCTestCase {
    func testAppSnapshotIndexIgnoresDuplicatePaths() {
        let first = AppSnapshot(
            name: "VirtualDesk",
            bundleID: "com.choco9527.virtualdesk",
            appPath: "/Applications/VirtualDesk.app",
            pid: 100,
            isRunning: true,
            iconPNGBase64: nil
        )
        let duplicate = AppSnapshot(
            name: "VirtualDesk Copy",
            bundleID: "com.choco9527.virtualdesk",
            appPath: "/Applications/VirtualDesk.app",
            pid: 101,
            isRunning: true,
            iconPNGBase64: nil
        )

        let indexed = AppSnapshotIndex.byPath([first, duplicate])

        XCTAssertEqual(indexed["/Applications/VirtualDesk.app"], first)
    }

    func testRejectsChromeWebAppShortcut() throws {
        let appURL = try makeAppBundle(
            name: "Google Drive.app",
            info: [
                "CFBundleExecutable": "app_mode_loader",
                "CFBundleIdentifier": "com.google.Chrome.app.test",
                "CFBundleName": "Google Drive",
                "CFBundlePackageType": "APPL",
                "CrAppModeShortcutURL": "https://drive.google.com/?lfhs=2",
                "CrBundleIdentifier": "com.google.Chrome",
            ]
        )

        XCTAssertTrue(AppBundlePolicy.isChromeWebAppBundle(url: appURL))
        XCTAssertFalse(AppBundlePolicy.isSupportedAppBundle(url: appURL))
    }

    func testRejectsScriptAppletBundle() throws {
        let appURL = try makeAppBundle(
            name: "GenericAgent.app",
            info: [
                "CFBundleExecutable": "applet",
                "CFBundleName": "GenericAgent",
                "CFBundlePackageType": "APPL",
                "CFBundleSignature": "aplt",
                "LSRequiresCarbon": true,
                "OSAAppletShowStartupScreen": false,
            ]
        )

        XCTAssertTrue(AppBundlePolicy.isScriptAppletBundle(url: appURL))
        XCTAssertFalse(AppBundlePolicy.isSupportedAppBundle(url: appURL))
    }

    func testAcceptsRegularAppBundle() throws {
        let appURL = try makeAppBundle(
            name: "Regular.app",
            info: [
                "CFBundleExecutable": "Regular",
                "CFBundleIdentifier": "com.example.Regular",
                "CFBundleName": "Regular",
                "CFBundlePackageType": "APPL",
            ]
        )

        XCTAssertFalse(AppBundlePolicy.isChromeWebAppBundle(url: appURL))
        XCTAssertTrue(AppBundlePolicy.isSupportedAppBundle(url: appURL))
    }

    private func makeAppBundle(name: String, info: [String: Any]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let appURL = root.appendingPathComponent(name, isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let plistURL = contentsURL.appendingPathComponent("Info.plist")

        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return appURL
    }
}
