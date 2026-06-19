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
        case "agent":
            runAgent()
        case "status":
            printStatus()
        case "start":
            startWorkspace()
        case "stop":
            stopWorkspace()
        case "create-screen":
            createScreen()
        case "list-apps":
            listApps()
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

    private func listApps() {
        do {
            try JSONOutput.print(AppListResult(apps: appService.listRunnableApps()))
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func runAgent() {
        do {
            let agent = VirtualDeskAgent(
                configuration: configuration,
                virtualDisplayProvisioner: virtualDisplayProvisioner,
                displayService: displayService,
                appService: appService,
                accessibilityService: accessibilityService
            )
            try agent.run()
        } catch {
            fail(error.localizedDescription)
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
            let agentLock = try AgentLock.acquire()
            let session = WorkspaceSession(
                configuration: configuration,
                virtualDisplayProvisioner: virtualDisplayProvisioner,
                displayService: displayService,
                appService: appService,
                accessibilityService: accessibilityService
            )
            let signalHandler = TerminationSignalHandler {
                AgentLog.info("Received termination signal. Cleaning up workspace.")
                _ = session.stop()
                Foundation.exit(0)
            }
            _ = try session.start(params: nil)
            withExtendedLifetime(agentLock) {
                withExtendedLifetime(signalHandler) {
                    RunLoop.main.run()
                }
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func stopWorkspace() {
        do {
            print(try ControlChannelClient.stopWorkspaceRawResponse())
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func createScreen() {
        do {
            let agentLock = try AgentLock.acquire()
            let session = WorkspaceSession(
                configuration: configuration,
                virtualDisplayProvisioner: virtualDisplayProvisioner,
                displayService: displayService,
                appService: appService,
                accessibilityService: accessibilityService
            )
            let controlChannel = ControlChannelServer(session: session)
            try controlChannel.start()
            let signalHandler = TerminationSignalHandler {
                AgentLog.info("Received termination signal. Cleaning up virtual display.")
                _ = session.stop()
                Foundation.exit(0)
            }

            let status = try session.startDisplay(params: nil)
            let displayID = status.display?.id ?? 0
            print("Created virtual display id=\(displayID). Press Ctrl-C to keep it alive.")

            withExtendedLifetime(agentLock) {
                withExtendedLifetime(controlChannel) {
                    withExtendedLifetime(signalHandler) {
                        RunLoop.current.run()
                    }
                }
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
          agent          Run persistent NDJSON agent over stdin/stdout
          start          Create a virtual display and keep Codex pinned to it
          stop           Stop the running workspace through the control socket
          status         Print current agent status as JSON
          create-screen  Create only the VirtualDesk virtual display
          list           List displays and mark likely BetterDisplay virtual displays
          list-apps      Print visible GUI apps as JSON
          pin            Move Codex to the target virtual display once
          watch          Keep Codex pinned to the target virtual display
          help           Show this help
        """)
    }

    private func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
        Foundation.exit(1)
    }
}
