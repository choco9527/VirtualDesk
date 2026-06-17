import CoreGraphics
import Foundation

final class WorkspaceOrchestrator {
    private let configuration: VirtualDeskConfiguration
    private let virtualDisplayProvisioner: VirtualDisplayProvisioning
    private let displayService: DisplayServicing
    private let appService: AppServicing
    private let accessibilityService: AccessibilityServicing
    private let stateStore: AgentStateStore

    init(
        configuration: VirtualDeskConfiguration,
        virtualDisplayProvisioner: VirtualDisplayProvisioning,
        displayService: DisplayServicing,
        appService: AppServicing,
        accessibilityService: AccessibilityServicing,
        stateStore: AgentStateStore = AgentStateStore()
    ) {
        self.configuration = configuration
        self.virtualDisplayProvisioner = virtualDisplayProvisioner
        self.displayService = displayService
        self.appService = appService
        self.accessibilityService = accessibilityService
        self.stateStore = stateStore
    }

    func start() throws {
        let agentLock = try AgentLock.acquire()

        try withExtendedLifetime(agentLock) {
            try startLocked()
        }
    }

    private func startLocked() throws {
        try stateStore.save(status(state: .starting, display: nil, window: nil, message: nil))

        let virtualDisplay = try virtualDisplayProvisioner.createDisplay(spec: displaySpec())
        let display = try waitForDisplay(id: virtualDisplay.displayID)

        AgentLog.info("Created virtual display \(display.name) id=\(display.id).")
        AgentLog.info("VirtualDesk is keeping the display alive. Press Ctrl-C to stop.")

        let guardian = WindowGuardian(
            configuration: configuration,
            displayService: FixedDisplayService(displayService: displayService, displayID: display.id),
            appService: appService,
            accessibilityService: accessibilityService
        )

        let stopController = StopController()
        let signalHandler = TerminationSignalHandler {
            AgentLog.info("Received termination signal. Cleaning up workspace.")
            stopController.requestStop()
        }

        guardian.enforceOnce()
        try saveRunningStatus(display: display)

        defer {
            saveStoppingStatus(display: display)
            restoreTargetWindowToPrimaryDisplay()
            stateStore.clear()
        }

        withExtendedLifetime(virtualDisplay) {
            withExtendedLifetime(signalHandler) {
                guardian.runUntilStopped(stopController.shouldStop)
            }
        }
    }

    private func displaySpec() -> VirtualDisplaySpec {
        VirtualDisplaySpec(
            name: configuration.virtualDisplayName,
            width: configuration.virtualDisplayWidth,
            height: configuration.virtualDisplayHeight,
            refreshRate: configuration.virtualDisplayRefreshRate
        )
    }

    private func waitForDisplay(id: CGDirectDisplayID) throws -> ManagedDisplay {
        for _ in 0..<30 {
            if let display = displayService.findDisplay(id: id) {
                return display
            }

            Thread.sleep(forTimeInterval: 0.2)
        }

        throw VirtualDeskError.virtualDisplayNotReady(id)
    }

    private func saveRunningStatus(display: ManagedDisplay) throws {
        let window = currentTargetWindowSnapshot()
        let status = status(state: .running, display: display, window: window, message: nil)
        try stateStore.save(status)
    }

    private func saveStoppingStatus(display: ManagedDisplay) {
        let window = currentTargetWindowSnapshot()
        let status = status(state: .stopping, display: display, window: window, message: "Cleaning up workspace.")
        try? stateStore.save(status)
    }

    private func status(
        state: WorkspaceState,
        display: ManagedDisplay?,
        window: WindowSnapshot?,
        message: String?
    ) -> AgentStatus {
        AgentStatus(
            state: state,
            pid: getpid(),
            display: display.map { DisplaySnapshot(display: $0, virtualDisplayID: display?.id) },
            targetApp: TargetAppSnapshot(path: configuration.targetAppPath, bundleID: nil),
            window: window,
            guardStatus: GuardSnapshot(
                enabled: state == .running,
                intervalMS: Int(configuration.guardianInterval * 1000)
            ),
            message: message
        )
    }

    private func currentTargetWindowSnapshot() -> WindowSnapshot? {
        guard let app = appService.runningApp(at: configuration.targetAppPath),
              let window = try? accessibilityService.primaryWindow(for: app),
              let rect = try? accessibilityService.frame(of: window) else {
            return nil
        }

        return WindowSnapshot(pid: app.processIdentifier, rect: RectSnapshot(rect: rect))
    }

    private func restoreTargetWindowToPrimaryDisplay() {
        guard let primaryDisplay = displayService.primaryDisplay(),
              let app = appService.runningApp(at: configuration.targetAppPath),
              let window = try? accessibilityService.primaryWindow(for: app) else {
            AgentLog.warning("Skip window restore: primary display, target app, or target window unavailable.")
            return
        }

        do {
            try accessibilityService.move(window: window, to: primaryDisplay.visibleFrame)
            AgentLog.info("Restored target window to \(primaryDisplay.name).")
        } catch {
            AgentLog.warning("Failed to restore target window: \(error.localizedDescription)")
        }
    }
}

private final class FixedDisplayService: DisplayServicing {
    private let displayService: DisplayServicing
    private let displayID: CGDirectDisplayID

    init(displayService: DisplayServicing, displayID: CGDirectDisplayID) {
        self.displayService = displayService
        self.displayID = displayID
    }

    func availableDisplays() -> [ManagedDisplay] {
        displayService.availableDisplays()
    }

    func findDisplay(id: CGDirectDisplayID) -> ManagedDisplay? {
        displayService.findDisplay(id: id)
    }

    func findDisplay(matching keywords: [String]) -> ManagedDisplay? {
        displayService.findDisplay(id: displayID)
    }

    func primaryDisplay() -> ManagedDisplay? {
        displayService.primaryDisplay()
    }
}
