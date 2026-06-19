import AppKit
import ApplicationServices

/// Reads notification badges of other apps by inspecting the Dock through the
/// Accessibility API. The Dock exposes each tile's badge as the private
/// `AXStatusLabel` attribute. Requires Accessibility permission.
enum DockBadgeReader {

    /// Prompt for Accessibility permission if not yet granted.
    @discardableResult
    static func ensureTrusted(prompt: Bool = true) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Returns a map of Dock tile title (app display name) -> badge label.
    /// Only tiles that currently show a badge are included.
    static func readBadges() -> [String: String] {
        guard let dock = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == "com.apple.dock" }) else {
            return [:]
        }

        let appElement = AXUIElementCreateApplication(dock.processIdentifier)
        guard let children = copyChildren(appElement) else { return [:] }

        var result: [String: String] = [:]
        for list in children {
            guard let items = copyChildren(list) else { continue }
            for item in items {
                guard let title = copyString(item, kAXTitleAttribute) else { continue }
                if let badge = copyString(item, "AXStatusLabel") {
                    result[title] = badge
                }
            }
        }
        return result
    }

    // MARK: - AX helpers

    private static func copyChildren(_ element: AXUIElement) -> [AXUIElement]? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success
        else { return nil }
        return ref as? [AXUIElement]
    }

    private static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success
        else { return nil }
        return ref as? String
    }
}
