import Foundation

/// State of a registered app.
/// (An app that is *not used* simply isn't in the registered list.)
enum AppMode: String, Codable, CaseIterable {
    case ignored    // registered but ignored (no icon, not in summary)
    case summary    // counted in the combined summary item
    case dedicated  // gets its own dedicated status bar icon

    var label: String {
        switch self {
        case .ignored: return "Ignored"
        case .summary: return "Summary"
        case .dedicated: return "Icon"
        }
    }
}

struct ManagedApp: Codable, Identifiable, Equatable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let path: String
    var mode: AppMode
}

/// A notification badge value.
enum Badge: Equatable {
    case none
    case dot           // empty badge (no number) -> counts as 1
    case count(Int)

    /// Numeric contribution to a summary.
    var value: Int {
        switch self {
        case .none: return 0
        case .dot: return 1
        case .count(let n): return n
        }
    }

    var isVisible: Bool { self != .none }

    /// Build a Badge from the Dock's `AXStatusLabel` string.
    static func from(label: String?) -> Badge {
        guard let label else { return .none }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .dot }
        if let n = Int(trimmed) { return .count(n) }
        // Non-numeric, non-empty (e.g. "•") -> treat as an empty badge.
        return .dot
    }
}
