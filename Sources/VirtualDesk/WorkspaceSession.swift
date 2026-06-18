import CoreGraphics
import Foundation

final class WorkspaceSession {
    private let baseConfiguration: VirtualDeskConfiguration
    private let virtualDisplayProvisioner: VirtualDisplayProvisioning
    private let displayService: DisplayServicing
    private let appService: AppServicing
    private let accessibilityService: AccessibilityServicing
    private let stateStore: AgentStateStore
    private let configurationStore: ConfigurationStore
    private let queue = DispatchQueue(label: "com.virtualdesk.workspace.session")

    private var activeConfiguration: VirtualDeskConfiguration?
    private var virtualDisplay: VirtualDisplayHandle?
    private var managedDisplay: ManagedDisplay?
    private var guardian: WindowGuardian?
    private var timer: DispatchSourceTimer?
    private var observers = WorkspaceObservers()
    private var pinnedAppPaths: [String] = []
    weak var eventSink: WorkspaceSessionEventSink?

    init(
        configuration: VirtualDeskConfiguration,
        virtualDisplayProvisioner: VirtualDisplayProvisioning,
        displayService: DisplayServicing,
        appService: AppServicing,
        accessibilityService: AccessibilityServicing,
        stateStore: AgentStateStore = AgentStateStore(),
        configurationStore: ConfigurationStore = ConfigurationStore()
    ) {
        self.baseConfiguration = configuration
        self.virtualDisplayProvisioner = virtualDisplayProvisioner
        self.displayService = displayService
        self.appService = appService
        self.accessibilityService = accessibilityService
        self.stateStore = stateStore
        self.configurationStore = configurationStore
    }

    deinit {
        stop()
    }

    func start(params: StartWorkspaceParams?) throws -> AgentStatus {
        try queue.sync {
            if virtualDisplay != nil {
                return try retargetWorkspace(params: params)
            }

            let configuration = try VirtualDeskConfiguration.resolved(
                base: baseConfiguration,
                config: configurationStore.load(),
                params: params
            )
            try stateStore.save(makeStatus(
                state: .starting,
                configuration: configuration,
                display: nil,
                message: nil
            ))

            let createdDisplay = try virtualDisplayProvisioner.createDisplay(spec: displaySpec(configuration: configuration))
            let display = try waitForDisplay(id: createdDisplay.displayID)
            let createdGuardian = WindowGuardian(
                configuration: configuration,
                displayService: fixedDisplayService(displayID: display.id),
                appService: appService,
                accessibilityService: accessibilityService
            )

            activeConfiguration = configuration
            virtualDisplay = createdDisplay
            managedDisplay = display
            guardian = createdGuardian
            pinnedAppPaths = [configuration.targetAppPath]
            try saveUserConfiguration(configuration: configuration, profile: params?.profile)
            observeWorkspaceLifecycle(configuration: configuration)
            handleGuardianResult(createdGuardian.enforceOnce(), configuration: configuration, display: display)
            startTimer(configuration: configuration, guardian: createdGuardian)

            let status = makeStatus(
                state: .running,
                configuration: configuration,
                display: display,
                message: nil
            )
            try stateStore.save(status)
            AgentLog.info("Started workspace on \(display.name) id=\(display.id).")
            emit(event: .workspaceStarted, status: status, reason: nil)
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

            let stopping = makeStatus(
                state: .stopping,
                configuration: configuration,
                display: managedDisplay,
                message: "Cleaning up workspace."
            )
            try? stateStore.save(stopping)

            timer?.cancel()
            timer = nil
            observers.removeAll()
            restorePinnedWindowsToPrimaryDisplay(fallbackConfiguration: configuration)
            guardian = nil
            managedDisplay = nil
            virtualDisplay = nil
            activeConfiguration = nil
            pinnedAppPaths = []
            stateStore.clear()
            AgentLog.info("Stopped workspace.")

            let status = AgentStatus.stopped(configuration: configuration)
            emit(event: .workspaceStopped, status: status, reason: nil)
            return status
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

    func listApps() -> AppListResult {
        AppListResult(apps: appService.listRunnableApps())
    }

    func captureScreen() throws -> ScreenCaptureResult {
        try queue.sync {
            guard let displayID = virtualDisplay?.displayID else {
                throw VirtualDeskError.workspaceNotRunning
            }

            return try ScreenCaptureService.capture(displayID: displayID)
        }
    }

    private func startTimer(configuration: VirtualDeskConfiguration, guardian: WindowGuardian) {
        let createdTimer = DispatchSource.makeTimerSource(queue: queue)
        createdTimer.schedule(
            deadline: .now() + configuration.guardianInterval,
            repeating: configuration.guardianInterval
        )
        createdTimer.setEventHandler { [weak self, weak guardian] in
            guard let self, let guardian else { return }
            let result = guardian.enforceOnce()
            guard let configuration = self.activeConfiguration,
                  let display = self.managedDisplay else {
                return
            }
            self.handleGuardianResult(result, configuration: configuration, display: display)
        }
        timer = createdTimer
        createdTimer.resume()
    }

    private func retargetWorkspace(params: StartWorkspaceParams?) throws -> AgentStatus {
        guard let configuration = activeConfiguration,
              let display = managedDisplay else {
            throw VirtualDeskError.workspaceNotRunning
        }

        let nextConfiguration = configuration.overriding(params)
        try nextConfiguration.validate()

        timer?.cancel()
        timer = nil
        observers.removeAll()

        let nextGuardian = WindowGuardian(
            configuration: nextConfiguration,
            displayService: fixedDisplayService(displayID: display.id),
            appService: appService,
            accessibilityService: accessibilityService
        )

        activeConfiguration = nextConfiguration
        guardian = nextGuardian
        rememberPinnedApp(path: nextConfiguration.targetAppPath)
        try saveUserConfiguration(configuration: nextConfiguration, profile: params?.profile)
        observeWorkspaceLifecycle(configuration: nextConfiguration)
        handleGuardianResult(nextGuardian.enforceOnce(), configuration: nextConfiguration, display: display)
        startTimer(configuration: nextConfiguration, guardian: nextGuardian)

        let status = makeStatus(
            state: .running,
            configuration: nextConfiguration,
            display: display,
            message: "Target app moved to workspace."
        )
        try stateStore.save(status)
        AgentLog.info("Retargeted workspace to \(nextConfiguration.targetAppPath).")
        return status
    }

    private func displaySpec(configuration: VirtualDeskConfiguration) -> VirtualDisplaySpec {
        VirtualDisplaySpec(
            name: configuration.virtualDisplayName,
            width: configuration.virtualDisplayWidth,
            height: configuration.virtualDisplayHeight,
            refreshRate: configuration.virtualDisplayRefreshRate
        )
    }

    private func fixedDisplayService(displayID: CGDirectDisplayID) -> DisplayServicing {
        FixedDisplayService(displayService: displayService, displayID: displayID)
    }

    private func saveUserConfiguration(configuration: VirtualDeskConfiguration, profile: String?) throws {
        try configurationStore.save(
            VirtualDeskUserConfig(
                appPath: configuration.targetAppPath,
                width: configuration.virtualDisplayWidth,
                height: configuration.virtualDisplayHeight,
                refreshRate: configuration.virtualDisplayRefreshRate,
                hiDPI: configuration.virtualDisplayHiDPI,
                profile: profile ?? VirtualDeskConfiguration.defaultProfileName
            )
        )
    }

    private func rememberPinnedApp(path: String) {
        guard !pinnedAppPaths.contains(path) else {
            return
        }

        pinnedAppPaths.append(path)
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
            targetApp: TargetAppSnapshot(
                path: configuration.targetAppPath,
                bundleID: appService.runningApp(at: configuration.targetAppPath)?.bundleIdentifier
            ),
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

    private func observeWorkspaceLifecycle(configuration: VirtualDeskConfiguration) {
        let appURL = URL(fileURLWithPath: configuration.targetAppPath)
        observers.observeDisplayChange { [weak self] in
            self?.queue.async {
                self?.handleDisplayChange()
            }
        }
        observers.observeAppLifecycle(
            bundleURL: appURL,
            onTerminate: { [weak self] in
                self?.queue.async {
                    self?.handleAppExited()
                }
            },
            onLaunch: { [weak self] in
                self?.queue.async {
                    self?.handleAppRelaunched()
                }
            }
        )
    }

    private func handleDisplayChange() {
        guard let configuration = activeConfiguration,
              let display = managedDisplay else {
            return
        }

        guard displayService.findDisplay(id: display.id) != nil else {
            let failed = makeStatus(
                state: .failed,
                configuration: configuration,
                display: display,
                message: "Virtual display was lost."
            )
            try? stateStore.save(failed)
            emit(event: .displayLost, status: failed, reason: "virtual_display_lost")
            emit(event: .workspaceFailed, status: failed, reason: "virtual_display_lost")
            cleanupFailedWorkspace(configuration: configuration)
            return
        }
    }

    private func handleAppExited() {
        guard let configuration = activeConfiguration else {
            return
        }

        let status = makeStatus(
            state: .running,
            configuration: configuration,
            display: managedDisplay,
            message: "Target app exited."
        )
        emit(event: .appExited, status: status, reason: "app_exited")
    }

    private func handleAppRelaunched() {
        guard let configuration = activeConfiguration,
              let guardian,
              let display = managedDisplay else {
            return
        }
        handleGuardianResult(guardian.enforceOnce(), configuration: configuration, display: display)
    }

    private func handleGuardianResult(
        _ result: GuardianEnforcementResult,
        configuration: VirtualDeskConfiguration,
        display: ManagedDisplay
    ) {
        guard result.recovered else {
            return
        }

        let status = makeStatus(
            state: .running,
            configuration: configuration,
            display: display,
            message: "Window recovered."
        )
        emit(event: .windowRecovered, status: status, reason: nil)
    }

    private func cleanupFailedWorkspace(configuration: VirtualDeskConfiguration) {
        timer?.cancel()
        timer = nil
        observers.removeAll()
        restorePinnedWindowsToPrimaryDisplay(fallbackConfiguration: configuration)
        guardian = nil
        managedDisplay = nil
        virtualDisplay = nil
        activeConfiguration = nil
        pinnedAppPaths = []
    }

    private func emit(event: WorkspaceEventName, status: AgentStatus, reason: String?) {
        eventSink?.workspaceSessionDidEmit(
            event: event,
            payload: WorkspaceEventPayload(status: status, reason: reason)
        )
    }

    private func restorePinnedWindowsToPrimaryDisplay(fallbackConfiguration: VirtualDeskConfiguration) {
        let paths = pinnedAppPaths.isEmpty ? [fallbackConfiguration.targetAppPath] : pinnedAppPaths
        paths.forEach { appPath in
            restoreWindowToPrimaryDisplay(appPath: appPath)
        }
    }

    private func restoreWindowToPrimaryDisplay(appPath: String) {
        guard let primaryDisplay = displayService.primaryDisplay(),
              let app = appService.runningApp(at: appPath),
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
