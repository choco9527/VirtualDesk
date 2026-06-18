import AppKit
import CoreGraphics
import Foundation

struct GuardianEnforcementResult {
    let recovered: Bool
}

final class WindowGuardian {
    private static let maxLaunchAttempts = 3

    private let configuration: VirtualDeskConfiguration
    private let displayService: DisplayServicing
    private let appService: AppServicing
    private let accessibilityService: AccessibilityServicing
    private var lastRecoveredFrame: CGRect?
    private var launchAttempts = 0

    init(
        configuration: VirtualDeskConfiguration,
        displayService: DisplayServicing,
        appService: AppServicing,
        accessibilityService: AccessibilityServicing
    ) {
        self.configuration = configuration
        self.displayService = displayService
        self.appService = appService
        self.accessibilityService = accessibilityService
    }

    func run() {
        runUntilStopped { false }
    }

    func runUntilStopped(_ shouldStop: () -> Bool) {
        while !shouldStop() {
            _ = enforceOnce()
            Thread.sleep(forTimeInterval: configuration.guardianInterval)
        }
    }

    @discardableResult
    func enforceOnce() -> GuardianEnforcementResult {
        do {
            let display = try targetDisplay()
            let app = try targetApp()
            let window = try accessibilityService.primaryWindow(for: app)
            let windowFrame = try accessibilityService.frame(of: window)

            if FramePolicy.shouldMove(windowFrame: windowFrame, targetFrame: display.visibleFrame) {
                try accessibilityService.move(window: window, to: display.visibleFrame)
                if lastRecoveredFrame != display.visibleFrame {
                    AgentLog.info("Recovered window to \(display.name).")
                    lastRecoveredFrame = display.visibleFrame
                    return GuardianEnforcementResult(recovered: true)
                }
            }
            return GuardianEnforcementResult(recovered: false)
        } catch {
            AgentLog.warning("Waiting: \(error.localizedDescription)")
            return GuardianEnforcementResult(recovered: false)
        }
    }

    @discardableResult
    func enforceWithRetry(attempts: Int = 5, delay: TimeInterval = 0.25) -> GuardianEnforcementResult {
        var latest = GuardianEnforcementResult(recovered: false)
        for attempt in 0..<attempts {
            latest = enforceOnce()
            if latest.recovered || attempt == attempts - 1 {
                return latest
            }
            Thread.sleep(forTimeInterval: delay)
        }
        return latest
    }

    private func targetDisplay() throws -> ManagedDisplay {
        guard let display = displayService.findDisplay(matching: configuration.targetDisplayKeywords) else {
            throw VirtualDeskError.targetDisplayNotFound(configuration.targetDisplayKeywords)
        }

        return display
    }

    private func targetApp() throws -> NSRunningApplication {
        if let app = appService.runningApp(at: configuration.targetAppPath) {
            launchAttempts = 0
            return app
        }

        guard launchAttempts < Self.maxLaunchAttempts else {
            throw VirtualDeskError.appNotRunning(
                "Launch limit reached for \(configuration.targetAppPath)."
            )
        }

        launchAttempts += 1
        return try appService.launchOrActivateApp(at: configuration.targetAppPath)
    }
}
