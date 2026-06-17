import CoreGraphics
import Foundation

final class WorkspaceSession {
    private let baseConfiguration: VirtualDeskConfiguration
    private let virtualDisplayProvisioner: VirtualDisplayProvisioning
    private let displayService: DisplayServicing
    private let appService: AppServicing
    private let accessibilityService: AccessibilityServicing
    private let stateStore: AgentStateStore
    private let queue = DispatchQueue(label: "com.virtualdesk.workspace.session")

    private var activeConfiguration: VirtualDeskConfiguration?
    private var virtualDisplay: VirtualDisplayHandle?
    private var managedDisplay: ManagedDisplay?
    private var guardian: WindowGuardian?
    private var timer: DispatchSourceTimer?

    init(
        configuration: VirtualDeskConfiguration,
        virtualDisplayProvisioner: VirtualDisplayProvisioning,
        displayService: DisplayServicing,
        appService: AppServicing,
        accessibilityService: AccessibilityServicing,
        stateStore: AgentStateStore = AgentStateStore()
    ) {
        self.baseConfiguration = configuration
        self.virtualDisplayProvisioner = virtualDisplayProvisioner
        self.displayService = displayService
        self.appService = appService
        self.accessibilityService = accessibilityService
        self.stateStore = stateStore
    }

    deinit {
        stop()
    }

    func start(params: StartWorkspaceParams?) throws -> AgentStatus {
        try queue.sync {
            guard virtualDisplay == nil else {
                throw VirtualDeskError.workspaceAlreadyRunning
            }

            let configuration = baseConfiguration.overriding(params)
            try stateStore.save(makeStatus(
                state: .starting,
                configuration: configuration,
                display: nil,
                message: nil
            ))

            let createdDisplay = try virtualDisplayProvisioner.createDisplay(spec: displaySpec(configuration: configuration))
            let display = try waitForDisplay(id: createdDisplay.displayID)
            let fixedDisplayService = FixedDisplayService(displayService: displayService, displayID: display.id)
            let createdGuardian = WindowGuardian(
                configuration: configuration,
                displayService: fixedDisplayService,
                appService: appService,
                accessibilityService: accessibilityService
            )

            activeConfiguration = configuration
            virtualDisplay = createdDisplay
            managedDisplay = display
            guardian = createdGuardian
            createdGuardian.enforceOnce()
            startTimer(configuration: configuration, guardian: createdGuardian)

            let status = makeStatus(
                state: .running,
                configuration: configuration,
                display: display,
                message: nil
            )
            try stateStore.save(status)
            AgentLog.info("Started workspace on \(display.name) id=\(display.id).")
            return status
        }
    }

    @discardableResult
    func stop() -> AgentStatus {
        queue.sync {
            guard let configuration = activeConfiguration else {
                let status = AgentStatus.stopped(configuration: baseConfiguration)
                stateStore.clear()
                return status
            }

            if let display = managedDisplay {
                let stopping = makeStatus(
                    state: .stopping,
                    configuration: configuration,
                    display: display,
                    message: "Cleaning up workspace."
                )
                try? stateStore.save(stopping)
            }

            timer?.cancel()
            timer = nil
            restoreTargetWindowToPrimaryDisplay(configuration: configuration)
            guardian = nil
            managedDisplay = nil
            virtualDisplay = nil
            activeConfiguration = nil
            stateStore.clear()
            AgentLog.info("Stopped workspace.")

            return AgentStatus.stopped(configuration: configuration)
        }
    }

    func status() -> AgentStatus {
        queue.sync {
            guard let configuration = activeConfiguration else {
                return AgentStatus.stopped(configuration: baseConfiguration)
            }

            return makeStatus(
                state: .running,
                configuration: configuration,
                display: managedDisplay,
                message: nil
            )
        }
    }

    func listDisplays() -> DisplayListResult {
        let virtualDisplayID = virtualDisplay?.displayID
        let displays = displayService.availableDisplays().map { display in
            DisplaySnapshot(display: display, virtualDisplayID: virtualDisplayID)
        }

        return DisplayListResult(displays: displays)
    }

    private func startTimer(configuration: VirtualDeskConfiguration, guardian: WindowGuardian) {
        let createdTimer = DispatchSource.makeTimerSource(queue: queue)
        createdTimer.schedule(
            deadline: .now() + configuration.guardianInterval,
            repeating: configuration.guardianInterval
        )
        createdTimer.setEventHandler { [weak guardian] in
            guardian?.enforceOnce()
        }
        timer = createdTimer
        createdTimer.resume()
    }

    private func displaySpec(configuration: VirtualDeskConfiguration) -> VirtualDisplaySpec {
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

    private func makeStatus(
        state: WorkspaceState,
        configuration: VirtualDeskConfiguration,
        display: ManagedDisplay?,
        message: String?
    ) -> AgentStatus {
        AgentStatus(
            state: state,
            pid: getpid(),
            display: display.map { DisplaySnapshot(display: $0, virtualDisplayID: virtualDisplay?.displayID) },
            targetApp: TargetAppSnapshot(path: configuration.targetAppPath, bundleID: nil),
            window: currentTargetWindowSnapshot(configuration: configuration),
            guardStatus: GuardSnapshot(
                enabled: state == .running,
                intervalMS: Int(configuration.guardianInterval * 1000)
            ),
            message: message
        )
    }

    private func currentTargetWindowSnapshot(configuration: VirtualDeskConfiguration) -> WindowSnapshot? {
        guard let app = appService.runningApp(at: configuration.targetAppPath),
              let window = try? accessibilityService.primaryWindow(for: app),
              let rect = try? accessibilityService.frame(of: window) else {
            return nil
        }

        return WindowSnapshot(pid: app.processIdentifier, rect: RectSnapshot(rect: rect))
    }

    private func restoreTargetWindowToPrimaryDisplay(configuration: VirtualDeskConfiguration) {
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
