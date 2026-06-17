import CoreGraphics
import Foundation

enum FramePolicy {
    static func shouldMove(
        windowFrame: CGRect,
        targetFrame: CGRect,
        tolerance: CGFloat = 8
    ) -> Bool {
        let insetFrame = targetFrame.insetBy(dx: -tolerance, dy: -tolerance)

        return !insetFrame.contains(windowFrame.origin)
            || abs(windowFrame.width - targetFrame.width) > tolerance
            || abs(windowFrame.height - targetFrame.height) > tolerance
    }
}
