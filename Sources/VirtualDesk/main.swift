import Foundation

AgentPresentationPolicy.applyIfNeeded(arguments: CommandLine.arguments)

let cli = VirtualDeskCLI(
    displayService: MacDisplayService(),
    virtualDisplayProvisioner: CGVirtualDisplayProvisioner(),
    appService: MacAppService(),
    accessibilityService: MacAccessibilityService()
)

cli.run(arguments: CommandLine.arguments)
