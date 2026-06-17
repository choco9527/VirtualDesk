import CoreGraphics
import Foundation

struct GuardianEnforcementResult {
    let recovered: Bool
}

final class WindowGuardian {
    private let configuration: VirtualDeskConfiguration
    private let displayService: DisplayServicing
    private let appService: AppServicing
    private let accessibilityService: AccessibilityServicing
    private var lastRecoveredFrame: CGRect?

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
            let app = try appService.launchOrActivateApp(at: configuration.targetAppPath)
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

    private func targetDisplay() throws -> ManagedDisplay {
        guard let display = displayService.findDisplay(matching: configuration.targetDisplayKeywords) else {
            throw VirtualDeskError.targetDisplayNotFound(configuration.targetDisplayKeywords)
        }

        return display
    }
}
