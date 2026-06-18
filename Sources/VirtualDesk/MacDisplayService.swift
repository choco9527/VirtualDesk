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

    func findDisplay(id: CGDirectDisplayID) -> ManagedDisplay? {
        if let screenDisplay = availableDisplays().first(where: { $0.id == id }) {
            return screenDisplay
        }

        guard onlineDisplayIDs().contains(id) else {
            return nil
        }

        let frame = CGDisplayBounds(id)
        return ManagedDisplay(
            id: id,
            name: "VirtualDesk Display \(id)",
            frame: frame,
            visibleFrame: frame
        )
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

    private func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else {
            return []
        }

        return Array(displays.prefix(Int(count)))
    }
}
