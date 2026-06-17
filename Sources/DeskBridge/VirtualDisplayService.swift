import CGVirtualDisplayBridge
import CoreGraphics
import Foundation

struct VirtualDisplaySpec {
    let name: String
    let width: UInt32
    let height: UInt32
    let refreshRate: Double
}

final class VirtualDisplayHandle {
    let displayID: CGDirectDisplayID
    private let rawDisplay: DBVirtualDisplayRef

    init(rawDisplay: DBVirtualDisplayRef, displayID: CGDirectDisplayID) {
        self.rawDisplay = rawDisplay
        self.displayID = displayID
    }

    deinit {
        DBVirtualDisplayRelease(rawDisplay)
    }
}

protocol VirtualDisplayProvisioning {
    func createDisplay(spec: VirtualDisplaySpec) throws -> VirtualDisplayHandle
}

final class CGVirtualDisplayProvisioner: VirtualDisplayProvisioning {
    func createDisplay(spec: VirtualDisplaySpec) throws -> VirtualDisplayHandle {
        var errorBuffer = [CChar](repeating: 0, count: 512)
        let rawDisplay = spec.name.withCString { name in
            DBVirtualDisplayCreate(
                name,
                spec.width,
                spec.height,
                spec.refreshRate,
                &errorBuffer,
                errorBuffer.count
            )
        }

        guard let rawDisplay else {
            let reason = String(cString: errorBuffer)
            throw DeskBridgeError.virtualDisplayCreateFailed(reason.isEmpty ? "Unknown error" : reason)
        }

        let displayID = DBVirtualDisplayGetDisplayID(rawDisplay)
        guard displayID != 0 else {
            DBVirtualDisplayRelease(rawDisplay)
            throw DeskBridgeError.virtualDisplayCreateFailed("Created display returned displayID=0.")
        }

        return VirtualDisplayHandle(rawDisplay: rawDisplay, displayID: displayID)
    }
}
