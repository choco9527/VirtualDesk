import CoreGraphics
import Foundation

struct DisplayLayoutItem: Equatable {
    let id: CGDirectDisplayID
    let frame: CGRect
}

struct DisplayPlacement: Equatable {
    let id: CGDirectDisplayID
    let x: Int32
    let y: Int32
}

enum DisplayArrangement {
    static let virtualDisplayGap: CGFloat = 80

    static func placeVirtualDisplay(
        id virtualDisplayID: CGDirectDisplayID,
        anchorDisplayID: CGDirectDisplayID
    ) -> Bool {
        let plan = placementPlan(
            displays: onlineDisplayLayouts(),
            virtualDisplayID: virtualDisplayID,
            anchorDisplayID: anchorDisplayID
        )
        guard !plan.isEmpty else {
            return false
        }

        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success,
              let configuration else {
            return false
        }

        for placement in plan {
            CGConfigureDisplayOrigin(configuration, placement.id, placement.x, placement.y)
        }

        return CGCompleteDisplayConfiguration(configuration, .forSession) == .success
    }

    static func placementPlan(
        displays: [DisplayLayoutItem],
        virtualDisplayID: CGDirectDisplayID,
        anchorDisplayID: CGDirectDisplayID
    ) -> [DisplayPlacement] {
        guard let anchor = displays.first(where: { $0.id == anchorDisplayID }) else {
            return []
        }

        let physicalDisplays = displays.filter { $0.id != virtualDisplayID }
        guard !physicalDisplays.isEmpty else {
            return []
        }

        let originOffset = CGPoint(x: anchor.frame.minX, y: anchor.frame.minY)
        let physicalPlacements = physicalDisplays.map { display in
            DisplayPlacement(
                id: display.id,
                x: Int32((display.frame.minX - originOffset.x).rounded()),
                y: Int32((display.frame.minY - originOffset.y).rounded())
            )
        }

        let rightEdge = physicalDisplays
            .map { $0.frame.maxX - originOffset.x }
            .max() ?? anchor.frame.width
        let virtualPlacement = DisplayPlacement(
            id: virtualDisplayID,
            x: Int32((rightEdge + virtualDisplayGap).rounded()),
            y: 0
        )

        return physicalPlacements + [virtualPlacement]
    }

    private static func onlineDisplayLayouts() -> [DisplayLayoutItem] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else {
            return []
        }

        return ids.prefix(Int(count)).map { id in
            DisplayLayoutItem(id: id, frame: CGDisplayBounds(id))
        }
    }
}
