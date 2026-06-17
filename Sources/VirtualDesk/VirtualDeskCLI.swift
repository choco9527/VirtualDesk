import Foundation

final class VirtualDeskCLI {
    private let displayService: DisplayServicing
    private let virtualDisplayProvisioner: VirtualDisplayProvisioning
    private let appService: AppServicing
    private let accessibilityService: AccessibilityServicing
    private let configuration = VirtualDeskConfiguration.pocDefault
    private let stateStore = AgentStateStore()

    init(
        displayService: DisplayServicing,
        virtualDisplayProvisioner: VirtualDisplayProvisioning,
        appService: AppServicing,
        accessibilityService: AccessibilityServicing
    ) {
        self.displayService = displayService
        self.virtualDisplayProvisioner = virtualDisplayProvisioner
        self.appService = appService
        self.accessibilityService = accessibilityService
    }

    func run(arguments: [String]) {
        let command = arguments.dropFirst().first ?? "pin"

        switch command {
        case "status":
            printStatus()
        case "start":
            startWorkspace()
        case "create-screen":
            createScreen()
        case "list":
            listDisplays()
        case "pin":
            pinOnce()
        case "watch":
            watch()
        case "help", "--help", "-h":
            printHelp()
        default:
            fail("Unknown command: \(command)")
        }
    }

    private func listDisplays() {
        let displays = displayService.availableDisplays()

        if displays.isEmpty {
            print("No displays found.")
            return
        }

        displays.forEach { display in
            let marker = display.matches(configuration.targetDisplayKeywords) ? "*" : " "
            print("\(marker) \(display.id) \(display.name) frame=\(display.frame) visible=\(display.visibleFrame)")
        }
    }

    private func printStatus() {
        do {
            let isRunning = AgentLock.isHeld()
            let savedStatus = stateStore.loadRawString()

            if isRunning, let savedStatus {
                print(savedStatus)
                return
            }

            if isRunning {
                try JSONOutput.print(AgentStatus.runningUnknown(
                    configuration: configuration,
                    pid: AgentLock.readPID(),
                    message: "VirtualDesk lock is held but no status file is available."
                ))
                return
            }

            let message = savedStatus == nil ? nil : "Removed stale status from previous run."
            if savedStatus != nil {
                stateStore.clear()
            }

            try JSONOutput.print(AgentStatus.stopped(configuration: configuration, message: message))
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func startWorkspace() {
        do {
            try ensureAccessibility()
            let orchestrator = WorkspaceOrchestrator(
                configuration: configuration,
                virtualDisplayProvisioner: virtualDisplayProvisioner,
                displayService: displayService,
                appService: appService,
                accessibilityService: accessibilityService
            )
            try orchestrator.start()
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func createScreen() {
        do {
            let display = try virtualDisplayProvisioner.createDisplay(spec: VirtualDisplaySpec(
                name: configuration.virtualDisplayName,
                width: configuration.virtualDisplayWidth,
                height: configuration.virtualDisplayHeight,
                refreshRate: configuration.virtualDisplayRefreshRate
            ))

            print("Created virtual display id=\(display.displayID). Press Ctrl-C to keep it alive.")
            withExtendedLifetime(display) {
                RunLoop.current.run()
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func pinOnce() {
        do {
            try ensureAccessibility()
            let display = try targetDisplay()
            let app = try appService.launchOrActivateApp(at: configuration.targetAppPath)
            let window = try accessibilityService.primaryWindow(for: app)
            try accessibilityService.move(window: window, to: display.visibleFrame)
            print("Pinned \(configuration.targetAppPath) to \(display.name).")
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func watch() {
        do {
            try ensureAccessibility()
            print("VirtualDesk watching \(configuration.targetAppPath). Press Ctrl-C to stop.")
            let guardian = WindowGuardian(
                configuration: configuration,
                displayService: displayService,
                appService: appService,
                accessibilityService: accessibilityService
            )
            guardian.run()
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func ensureAccessibility() throws {
        guard accessibilityService.isTrusted(prompt: true) else {
            throw VirtualDeskError.accessibilityPermissionMissing
        }
    }

    private func targetDisplay() throws -> ManagedDisplay {
        guard let display = displayService.findDisplay(matching: configuration.targetDisplayKeywords) else {
            throw VirtualDeskError.targetDisplayNotFound(configuration.targetDisplayKeywords)
        }

        return display
    }

    private func printHelp() {
        print("""
        VirtualDesk POC

        Commands:
          start          Create a virtual display and keep Codex pinned to it
          status         Print current agent status as JSON
          create-screen  Create only the VirtualDesk virtual display
          list   List displays and mark likely BetterDisplay virtual displays
          pin    Move Codex to the target virtual display once
          watch  Keep Codex pinned to the target virtual display
          help   Show this help
        """)
    }

    private func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
        Foundation.exit(1)
    }
}
