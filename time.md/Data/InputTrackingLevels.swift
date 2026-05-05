import Foundation

/// How granularly keystrokes are recorded. Each step up enables a richer
/// downstream view but stores more about what the user typed.
enum KeystrokeTrackingLevel: String, CaseIterable, Identifiable, Sendable {
    /// Don't capture keystrokes at all.
    case off
    /// Timestamps only — no key codes, no characters. Powers the typing-intensity
    /// timeline (count over time) and per-app activity counts.
    case activity
    /// Timestamps + virtual key codes. Powers intensity + most-pressed-keys.
    /// Still no characters, so passwords and message content stay out of the DB.
    case perKey
    /// Timestamps + key codes + actual characters. Powers "top typed words".
    /// High privacy cost — treat the database like a password vault.
    case fullContent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .activity: return "Activity only"
        case .perKey: return "Per-key counts"
        case .fullContent: return "Full content"
        }
    }

    var summary: String {
        switch self {
        case .off:
            return "Don't capture any keystrokes."
        case .activity:
            return "Timestamps only. Powers typing-intensity charts. No key codes, no characters."
        case .perKey:
            return "Timestamps + key codes. Powers intensity + most-pressed keys. No characters stored."
        case .fullContent:
            return "Stores the actual letters you type. Powers \"top typed words.\" Privacy cost is high — secure-input fields are still redacted, but most apps don't enable Secure Input."
        }
    }

    var capturesKeyCode: Bool {
        switch self {
        case .off, .activity: return false
        case .perKey, .fullContent: return true
        }
    }

    var capturesContent: Bool { self == .fullContent }

    var isOff: Bool { self == .off }
}

/// How granularly cursor events are recorded. Each step up captures more event
/// kinds. The heatmap aggregator only consumes movement events regardless of
/// level — clicks/scrolls are kept for raw queries via MCP.
enum CursorTrackingLevel: String, CaseIterable, Identifiable, Sendable {
    /// Don't capture cursor events.
    case off
    /// Movement and drags only — feeds the cursor heatmap.
    case heatmap
    /// Movement + drags + click events.
    case heatmapAndClicks
    /// Everything: move, drag, click, scroll. Highest storage cost.
    case fullTrail

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .heatmap: return "Heatmap only"
        case .heatmapAndClicks: return "Heatmap + clicks"
        case .fullTrail: return "Full event trail"
        }
    }

    var summary: String {
        switch self {
        case .off:
            return "Don't capture cursor events."
        case .heatmap:
            return "Cursor positions while moving or dragging. Powers the heatmap. ~30 events/second when active."
        case .heatmapAndClicks:
            return "Movement plus click locations. Adds where-you-click insights."
        case .fullTrail:
            return "Every move, drag, click, and scroll. Highest storage; keep retention short."
        }
    }

    var capturesClicks: Bool {
        switch self {
        case .off, .heatmap: return false
        case .heatmapAndClicks, .fullTrail: return true
        }
    }

    var capturesScrolls: Bool { self == .fullTrail }

    var isOff: Bool { self == .off }
}
