import AppKit
import CoreGraphics
import Foundation

final class MacDisplayService: DisplayServicing {
    func availableDisplays() -> [ManagedDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return nil
            }

            return ManagedDisplay(
                id: id,
                name: screen.localizedName,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame
            )
        }
    }

    func primaryDisplay() -> ManagedDisplay? {
        guard let screen = NSScreen.main,
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return availableDisplays().first
        }

        return ManagedDisplay(
            id: id,
            name: screen.localizedName,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame
        )
    }
}
