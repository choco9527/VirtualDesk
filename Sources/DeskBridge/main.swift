import Foundation

let cli = DeskBridgeCLI(
    displayService: MacDisplayService(),
    virtualDisplayProvisioner: CGVirtualDisplayProvisioner(),
    appService: MacAppService(),
    accessibilityService: MacAccessibilityService()
)

cli.run(arguments: CommandLine.arguments)
