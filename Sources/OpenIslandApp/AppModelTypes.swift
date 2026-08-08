import AppKit
import CoreGraphics
import Foundation
import OpenIslandCore

enum NotchStatus: Equatable {
    case closed
    case opened
    case popping
}

enum NotchOpenReason: Equatable {
    case click
    case hover
    case notification
    case boot
    /// The session switcher, which reuses the expanded panel rather than
    /// standing up a second window that would have to stay in step with it.
    case switcher
    /// A gesture needs its own reason so its intentional feedback never turns
    /// ordinary pointer-driven opens into a stream of sounds.
    case handGesture
}

enum TrackedEventIngress {
    case bridge
    case rollout
}

// MARK: - v6 island preferences

/// What the closed island renders in the right slot. Chosen in the
/// Personalization tab; the pill layout only varies by content width.
enum IslandRightSlot: String, CaseIterable, Identifiable, Sendable {
    case count   // "×N" badge
    case agents  // colored dot stack, one per active agent tool
    case none    // pill collapses — useful if you just want the bars

    var id: String { rawValue }
}

/// What the closed island renders in the center label (external displays
/// only — on MacBook the physical notch covers this space so we suppress
/// the label regardless).
enum IslandCenterLabel: String, CaseIterable, Identifiable, Sendable {
    case sessionName  // e.g. "open-island"
    case agentAction  // e.g. "Claude · editing"
    case off

    var id: String { rawValue }
}

/// How much the closed island says about what is running.
///
/// Not stored: it is a preset over `IslandRightSlot` and `IslandCenterLabel`,
/// which already express this more finely. Keeping a third copy of the same
/// state would let the two disagree.
enum MenuBarLayout: String, CaseIterable, Identifiable, Sendable {
    case clean
    case detailed

    var id: String { rawValue }

    var labelKey: String { "settings.display.layout.\(rawValue)" }
    var detailKey: String { "settings.display.layout.\(rawValue).help" }

    var rightSlot: IslandRightSlot { self == .clean ? .count : .agents }
    var centerLabel: IslandCenterLabel { self == .clean ? .off : .agentAction }

    static func resolved(rightSlot: IslandRightSlot, centerLabel: IslandCenterLabel) -> MenuBarLayout {
        centerLabel == .off ? .clean : .detailed
    }
}

// MARK: - v8 island preferences

enum IslandAppearanceDisplayProfile: String, CaseIterable, Identifiable, Sendable {
    case notch
    case topBar

    var id: String { rawValue }
}

struct IslandAppearancePreferences: Equatable, Sendable {
    var rightSlot: IslandRightSlot = .count
    var centerLabel: IslandCenterLabel = .agentAction
    var usageDisplay: IslandUsageDisplay = .compact
    var sessionStateIndicator: IslandSessionStateIndicator = .animatedDot
    var sessionGroup: IslandSessionGroup = .none
    var sessionSort: IslandSessionSort = .attention
    var completedStaleThreshold: IslandCompletedStaleThreshold = .fiveMinutes
}

enum IslandUsageDisplay: String, CaseIterable, Identifiable, Sendable {
    case hidden
    case compact

    var id: String { rawValue }
}

enum IslandSessionStateIndicator: String, CaseIterable, Identifiable, Sendable {
    case animatedDot
    case bar
    case glyph
    case tint

    var id: String { rawValue }

    func timelineInterval(presence: IslandSessionPresence, isActionable: Bool) -> TimeInterval? {
        guard self == .animatedDot else { return nil }
        return presence == .running || isActionable ? 1.0 / 15.0 : nil
    }
}

enum IslandSessionGroup: String, CaseIterable, Identifiable, Sendable {
    case none
    case state
    case agent
    case project

    var id: String { rawValue }
}

enum IslandSessionSort: String, CaseIterable, Identifiable, Sendable {
    case attention
    case lastUpdate

    var id: String { rawValue }
}

enum IslandCompletedStaleThreshold: String, CaseIterable, Identifiable, Sendable {
    case twoMinutes
    case fiveMinutes
    case tenMinutes
    case twentyMinutes
    case never

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .twoMinutes:    return 2 * 60
        case .fiveMinutes:   return 5 * 60
        case .tenMinutes:    return 10 * 60
        case .twentyMinutes: return 20 * 60
        case .never:         return .infinity
        }
    }
}

struct IslandSessionSection: Identifiable {
    let id: String
    let title: String
    let sessions: [AgentSession]
}
