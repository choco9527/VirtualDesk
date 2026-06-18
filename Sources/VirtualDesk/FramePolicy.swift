import CoreGraphics
import Foundation

enum FramePolicy {
    static func shouldMove(
        windowFrame: CGRect,
        targetFrame: CGRect,
        tolerance: CGFloat = 8
    ) -> Bool {
        let allowedFrame = targetFrame.insetBy(dx: -tolerance, dy: -tolerance)
        return !allowedFrame.contains(windowFrame)
    }
}
