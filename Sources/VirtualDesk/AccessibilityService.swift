import AppKit
import ApplicationServices
import Foundation

struct ManagedWindow {
    let app: NSRunningApplication
    let element: AXUIElement
}

protocol AccessibilityServicing {
    func isTrusted(prompt: Bool) -> Bool
    func primaryWindow(for app: NSRunningApplication) throws -> ManagedWindow
    func move(window: ManagedWindow, to frame: CGRect) throws
    func frame(of window: ManagedWindow) throws -> CGRect
}

final class MacAccessibilityService: AccessibilityServicing {
    func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary

        return AXIsProcessTrustedWithOptions(options)
    }

    func primaryWindow(for app: NSRunningApplication) throws -> ManagedWindow {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let focusedWindow = try windowAttribute(kAXFocusedWindowAttribute, appElement: appElement)

        if let focusedWindow {
            return ManagedWindow(app: app, element: focusedWindow)
        }

        if let firstWindow = try windows(appElement: appElement).first {
            return ManagedWindow(app: app, element: firstWindow)
        }

        throw VirtualDeskError.windowNotFound(app.localizedName ?? app.bundleIdentifier ?? "target app")
    }

    func move(window: ManagedWindow, to frame: CGRect) throws {
        try set(point: frame.origin, attribute: kAXPositionAttribute, element: window.element)
        try set(size: frame.size, attribute: kAXSizeAttribute, element: window.element)
    }

    func frame(of window: ManagedWindow) throws -> CGRect {
        let position = try point(attribute: kAXPositionAttribute, element: window.element)
        let size = try size(attribute: kAXSizeAttribute, element: window.element)

        return CGRect(origin: position, size: size)
    }

    private func windowAttribute(
        _ attribute: String,
        appElement: AXUIElement
    ) throws -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, attribute as CFString, &value)

        if result == .success {
            return (value as! AXUIElement)
        }

        if result == .attributeUnsupported || result == .noValue {
            return nil
        }

        throw VirtualDeskError.windowMoveFailed("AX read \(attribute) failed with \(result.rawValue).")
    }

    private func windows(appElement: AXUIElement) throws -> [AXUIElement] {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)

        if result == .success {
            return (value as? [AXUIElement]) ?? []
        }

        throw VirtualDeskError.windowMoveFailed("AX read windows failed with \(result.rawValue).")
    }

    private func point(attribute: String, element: AXUIElement) throws -> CGPoint {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)

        guard result == .success, let axValue = value else {
            throw VirtualDeskError.windowMoveFailed("AX read \(attribute) failed with \(result.rawValue).")
        }

        var point = CGPoint.zero
        AXValueGetValue(axValue as! AXValue, .cgPoint, &point)
        return point
    }

    private func size(attribute: String, element: AXUIElement) throws -> CGSize {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)

        guard result == .success, let axValue = value else {
            throw VirtualDeskError.windowMoveFailed("AX read \(attribute) failed with \(result.rawValue).")
        }

        var size = CGSize.zero
        AXValueGetValue(axValue as! AXValue, .cgSize, &size)
        return size
    }

    private func set(point: CGPoint, attribute: String, element: AXUIElement) throws {
        var mutablePoint = point
        guard let value = AXValueCreate(.cgPoint, &mutablePoint) else {
            throw VirtualDeskError.windowMoveFailed("Could not create AX point value.")
        }

        try set(value: value, attribute: attribute, element: element)
    }

    private func set(size: CGSize, attribute: String, element: AXUIElement) throws {
        var mutableSize = size
        guard let value = AXValueCreate(.cgSize, &mutableSize) else {
            throw VirtualDeskError.windowMoveFailed("Could not create AX size value.")
        }

        try set(value: value, attribute: attribute, element: element)
    }

    private func set(value: AXValue, attribute: String, element: AXUIElement) throws {
        let result = AXUIElementSetAttributeValue(element, attribute as CFString, value)

        guard result == .success else {
            throw VirtualDeskError.windowMoveFailed("AX set \(attribute) failed with \(result.rawValue).")
        }
    }
}
