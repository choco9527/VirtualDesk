import CoreGraphics
import Foundation

struct ManagedDisplay {
    let id: CGDirectDisplayID
    let name: String
    let frame: CGRect
    let visibleFrame: CGRect

    func matches(_ keywords: [String]) -> Bool {
        keywords.contains { keyword in
            name.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

protocol DisplayServicing {
    func availableDisplays() -> [ManagedDisplay]
    func findDisplay(id: CGDirectDisplayID) -> ManagedDisplay?
    func findDisplay(matching keywords: [String]) -> ManagedDisplay?
    func primaryDisplay() -> ManagedDisplay?
}

extension DisplayServicing {
    func findDisplay(id: CGDirectDisplayID) -> ManagedDisplay? {
        availableDisplays().first { display in
            display.id == id
        }
    }

    func findDisplay(matching keywords: [String]) -> ManagedDisplay? {
        availableDisplays().first { display in
            display.matches(keywords)
        }
    }

    func primaryDisplay() -> ManagedDisplay? {
        availableDisplays().first
    }
}
