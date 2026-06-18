import AppKit
import CoreGraphics
import Foundation

enum ScreenCaptureService {
    static func isAuthorized() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func capture(displayID: CGDirectDisplayID) throws -> ScreenCaptureResult {
        guard isAuthorized() else {
            throw VirtualDeskError.screenCapturePermissionMissing
        }

        guard let image = CGDisplayCreateImage(displayID) else {
            throw VirtualDeskError.screenCaptureUnavailable(
                "CGDisplayCreateImage returned nil. Screen Recording permission may be required."
            )
        }

        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw VirtualDeskError.screenCaptureUnavailable("Failed to encode display image as PNG.")
        }

        return ScreenCaptureResult(
            displayID: displayID,
            mimeType: "image/png",
            imageBase64: pngData.base64EncodedString()
        )
    }
}
