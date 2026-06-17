import CoreGraphics
import Foundation

final class WindowGuardian {
    private let configuration: VirtualDeskConfiguration
    private let displayService: DisplayServicing
    private let appService: AppServicing
    private let accessibilityService: AccessibilityServicing

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
            enforceOnce()
            Thread.sleep(forTimeInterval: configuration.guardianInterval)
        }
    }

    func enforceOnce() {
        do {
            let display = try targetDisplay()
            let app = try appService.launchOrActivateApp(at: configuration.targetAppPath)
            let window = try accessibilityService.primaryWindow(for: app)
            let windowFrame = try accessibilityService.frame(of: window)

            if FramePolicy.shouldMove(windowFrame: windowFrame, targetFrame: display.visibleFrame) {
                try accessibilityService.move(window: window, to: display.visibleFrame)
                AgentLog.info("Recovered window to \(display.name).")
            }
        } catch {
            AgentLog.warning("Waiting: \(error.localizedDescription)")
        }
    }

    private func targetDisplay() throws -> ManagedDisplay {
        guard let display = displayService.findDisplay(matching: configuration.targetDisplayKeywords) else {
            throw VirtualDeskError.targetDisplayNotFound(configuration.targetDisplayKeywords)
        }

        return display
    }
}
