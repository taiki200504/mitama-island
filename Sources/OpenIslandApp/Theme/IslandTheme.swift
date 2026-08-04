import SwiftUI

/// How a theme rounds off a card, a button or a badge.
enum IslandCornerStyle: Equatable, Sendable {
    case rounded
    /// Two opposite corners cut on the diagonal instead of curved. The signature
    /// shape of a heads-up display, and what separates the two themes at a
    /// glance even in a screenshot with no colour.
    case chamfered
}

/// Colours for the four states a session can be in.
struct IslandStatusTints: Sendable {
    var running: Color
    var waitingForApproval: Color
    var waitingForAnswer: Color
    var completed: Color
    /// Several sessions waiting at once, shown on the closed island.
    var waitingAggregate: Color
    /// Reserved for failure. Nothing uses it yet — the app has no error state.
    var critical: Color
}

/// The whole visual language, in one value.
///
/// Read through `IslandTheme.current` rather than an `Environment` value: the
/// palette is also needed from `ButtonStyle`, `Shape` and plain helper functions,
/// none of which have an environment to read from. Threading it through every
/// one of those would be a far larger change than this indirection.
protocol IslandTheme: Sendable {
    var id: IslandThemeID { get }
    /// The panel's own background.
    var ink: Color { get }
    /// Text and anything drawn on top of `ink`.
    var paper: Color { get }
    /// The one colour that means "this is the app talking".
    var accent: Color { get }
    var statusTints: IslandStatusTints { get }
    var cornerStyle: IslandCornerStyle { get }
    /// How far a glow bleeds past its shape. Zero switches glows off entirely.
    var glowRadius: CGFloat { get }
}

enum IslandThemeID: String, CaseIterable, Identifiable, Sendable {
    /// The heads-up-display look: cool, angular, lit from within.
    case hud
    /// What the app looked like before themes existed: warm paper on black.
    case classic

    var id: String { rawValue }
    var labelKey: String { "settings.appearance.theme.\(rawValue)" }

    var theme: any IslandTheme {
        switch self {
        case .hud: HUDTheme()
        case .classic: ClassicTheme()
        }
    }
}

extension IslandTheme {
    /// The shape a card, button or badge should use at this corner size.
    func shape(cornerRadius: CGFloat) -> AnyShape {
        switch cornerStyle {
        case .rounded:
            AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        case .chamfered:
            AnyShape(ChamferedRectangle(cut: cornerRadius))
        }
    }
}

// MARK: - The themes

/// Cool, angular, lit from within.
struct HUDTheme: IslandTheme {
    let id = IslandThemeID.hud

    // Not pure black. The notch itself is pure black, so a panel that is very
    // slightly blue is what gives it an edge against the hardware.
    let ink = Color(hex: 0x050A12)
    let paper = Color(hex: 0xDFF3FF)
    let accent = Color(hex: 0x3FD8FF)

    let statusTints = IslandStatusTints(
        running: Color(hex: 0x3FD8FF),
        // Amber for the two states that are waiting on the user. Warm against a
        // cold panel is what makes them the thing your eye lands on.
        waitingForApproval: Color(hex: 0xFF9F45),
        waitingForAnswer: Color(hex: 0xFFD65C),
        completed: Color(hex: 0x5AF0C8),
        waitingAggregate: Color(hex: 0xFFB765),
        critical: Color(hex: 0xFF4A6E)
    )

    let cornerStyle = IslandCornerStyle.chamfered
    let glowRadius: CGFloat = 2.5
}

/// The original look, kept so the change is reversible.
struct ClassicTheme: IslandTheme {
    let id = IslandThemeID.classic

    let ink = Color(hex: 0x0D0D0F)
    let paper = Color(hex: 0xF1EAD9)
    let accent = Color(hex: 0x6EA7FF)

    let statusTints = IslandStatusTints(
        running: Color(hex: 0x6EA7FF),
        waitingForApproval: Color(hex: 0xF4A4A4),
        waitingForAnswer: Color(hex: 0xFFD58A),
        completed: Color(hex: 0x6FB982),
        waitingAggregate: Color(hex: 0xE7A762),
        critical: Color(hex: 0xF4A4A4)
    )

    let cornerStyle = IslandCornerStyle.rounded
    let glowRadius: CGFloat = 2.5
}

// MARK: - The current theme

extension IslandTheme where Self == HUDTheme {
    /// The theme every palette lookup goes through.
    ///
    /// Resolved from `UserDefaults` on each read rather than cached: the value is
    /// two enum cases wide, reads are cheap, and a cache would need invalidating
    /// from the settings pane — one more thing to get wrong for no measurable
    /// gain.
    @MainActor
    static var current: any IslandTheme {
        let raw = UserDefaults.standard.string(forKey: DisplaySettings.Keys.theme)
        return (IslandThemeID(rawValue: raw ?? "") ?? .hud).theme
    }
}

/// Shorthand so call sites read as `IslandThemes.current.accent`.
@MainActor
enum IslandThemes {
    static var current: any IslandTheme { HUDTheme.current }
}

extension Color {
    /// `0xRRGGBB`, which is how the palette above is easiest to check against a
    /// colour picker.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
