import Foundation

final class VirtualDeskAgent: WorkspaceSessionEventSink {
    private let accessibilityService: AccessibilityServicing
    private let session: WorkspaceSession
    private let router = IORouter()
    private var agentLock: AgentLock?
    private var signalHandler: TerminationSignalHandler?
    private var controlChannel: ControlChannelServer?

    init(
        configuration: VirtualDeskConfiguration,
        virtualDisplayProvisioner: VirtualDisplayProvisioning,
        displayService: DisplayServicing,
        appService: AppServicing,
        accessibilityService: AccessibilityServicing
    ) {
        self.accessibilityService = accessibilityService
        self.session = WorkspaceSession(
            configuration: configuration,
            virtualDisplayProvisioner: virtualDisplayProvisioner,
            displayService: displayService,
            appService: appService,
            accessibilityService: accessibilityService
        )
        self.session.eventSink = self
    }

    func run() throws -> Never {
        agentLock = try AgentLock.acquire()
        controlChannel = ControlChannelServer(session: session)
        try controlChannel?.start()
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

    func workspaceSessionDidEmit(event: WorkspaceEventName, payload: WorkspaceEventPayload) {
        router.sendEvent(AgentEvent(event: event.rawValue, data: payload))
    }

    private func handle(data: Data) {
        do {
            let request = try JSONDecoder.virtualDesk.decode(BasicCommandRequest.self, from: data)

            switch request.method {
            case .capabilities:
                sendCapabilities(id: request.id)
            case .status:
                sendStatus(id: request.id)
            case .accessibilityStatus:
                sendAccessibilityStatus(id: request.id, prompt: false)
            case .requestAccessibility:
                sendAccessibilityStatus(id: request.id, prompt: true)
            case .listDisplays:
                sendDisplayList(id: request.id)
            case .listApps:
                sendAppList(id: request.id)
            case .captureScreen:
                sendScreenCapture(id: request.id)
            case .startWorkspace:
                try startWorkspace(data: data)
            case .stopWorkspace:
                stopWorkspace(id: request.id)
            }
        } catch {
            let payload = (error as? VirtualDeskError)?.payload
                ?? VirtualDeskError.invalidCommand(error.localizedDescription).payload
            router.sendFailure(id: "unknown", error: payload)
        }
    }

    private func sendCapabilities(id: String) {
        let result = CapabilitiesResult(
            platform: "macos",
            protocolVersion: "1.0",
            supports: AgentSupportFlags(
                virtualDisplay: true,
                windowControl: true,
                stopWorkspace: true,
                listApps: true,
                captureScreen: true
            )
        )
        router.send(CommandResponse.success(id: id, result: result))
    }

    private func sendStatus(id: String) {
        router.send(CommandResponse.success(id: id, result: session.status()))
    }

    private func sendDisplayList(id: String) {
        router.send(CommandResponse.success(id: id, result: session.listDisplays()))
    }

    private func sendAppList(id: String) {
        router.send(CommandResponse.success(id: id, result: session.listApps()))
    }

    private func sendScreenCapture(id: String) {
        do {
            router.send(CommandResponse.success(id: id, result: try session.captureScreen()))
        } catch {
            let payload = (error as? VirtualDeskError)?.payload
                ?? VirtualDeskError.internalError(error.localizedDescription).payload
            router.sendFailure(id: id, error: payload)
        }
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
                error: VirtualDeskError.accessibilityPermissionMissing.payload
            )
            return
        }

        do {
            let status = try session.start(params: request.params)
            router.send(CommandResponse.success(id: request.id, result: status))
        } catch {
            let payload = (error as? VirtualDeskError)?.payload
                ?? VirtualDeskError.internalError(error.localizedDescription).payload
            router.sendFailure(id: request.id, error: payload)
        }
    }

    private func stopWorkspace(id: String) {
        let status = session.stop()
        router.send(CommandResponse.success(id: id, result: status))
    }
}
