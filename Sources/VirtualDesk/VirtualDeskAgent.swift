import Foundation

final class VirtualDeskAgent {
    private let configuration: VirtualDeskConfiguration
    private let accessibilityService: AccessibilityServicing
    private let session: WorkspaceSession
    private let router = IORouter()
    private var agentLock: AgentLock?
    private var signalHandler: TerminationSignalHandler?

    init(
        configuration: VirtualDeskConfiguration,
        virtualDisplayProvisioner: VirtualDisplayProvisioning,
        displayService: DisplayServicing,
        appService: AppServicing,
        accessibilityService: AccessibilityServicing
    ) {
        self.configuration = configuration
        self.accessibilityService = accessibilityService
        self.session = WorkspaceSession(
            configuration: configuration,
            virtualDisplayProvisioner: virtualDisplayProvisioner,
            displayService: displayService,
            appService: appService,
            accessibilityService: accessibilityService
        )
    }

    func run() throws -> Never {
        agentLock = try AgentLock.acquire()
        signalHandler = TerminationSignalHandler { [weak self] in
            AgentLog.info("Received termination signal. Cleaning up workspace.")
            _ = self?.session.stop()
            Foundation.exit(0)
        }

        router.startListening { [weak self] data in
            self?.handle(data: data)
        }

        AgentLog.info("VirtualDesk agent is running.")
        RunLoop.main.run()
        Foundation.exit(0)
    }

    private func handle(data: Data) {
        do {
            let request = try JSONDecoder.virtualDesk.decode(BasicCommandRequest.self, from: data)

            switch request.method {
            case .status:
                sendStatus(id: request.id)
            case .accessibilityStatus:
                sendAccessibilityStatus(id: request.id, prompt: false)
            case .requestAccessibility:
                sendAccessibilityStatus(id: request.id, prompt: true)
            case .listDisplays:
                sendDisplayList(id: request.id)
            case .startWorkspace:
                try startWorkspace(data: data)
            case .stopWorkspace:
                stopWorkspace(id: request.id)
            }
        } catch {
            AgentLog.error("Invalid command: \(error.localizedDescription)")
        }
    }

    private func sendStatus(id: String) {
        router.send(CommandResponse.success(id: id, result: session.status()))
    }

    private func sendDisplayList(id: String) {
        router.send(CommandResponse.success(id: id, result: session.listDisplays()))
    }

    private func sendAccessibilityStatus(id: String, prompt: Bool) {
        let trusted = accessibilityService.isTrusted(prompt: prompt)
        let result = AccessibilityResult(
            trusted: trusted,
            promptShown: prompt && !trusted,
            message: trusted ? nil : "Enable VirtualDesk in System Settings > Privacy & Security > Accessibility."
        )

        router.send(CommandResponse.success(id: id, result: result))
    }

    private func startWorkspace(data: Data) throws {
        let request = try JSONDecoder.virtualDesk.decode(
            CommandRequest<StartWorkspaceParams>.self,
            from: data
        )

        guard accessibilityService.isTrusted(prompt: true) else {
            router.sendFailure(
                id: request.id,
                error: VirtualDeskError.accessibilityPermissionMissing.localizedDescription
            )
            return
        }

        do {
            let status = try session.start(params: request.params)
            router.send(CommandResponse.success(id: request.id, result: status))
        } catch {
            router.sendFailure(id: request.id, error: error.localizedDescription)
        }
    }

    private func stopWorkspace(id: String) {
        let status = session.stop()
        router.send(CommandResponse.success(id: id, result: status))
        router.sendEvent(AgentEvent(event: "workspace_stopped", data: status))
    }
}
