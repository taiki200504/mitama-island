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

/// Motion values that make the island feel responsive without turning every
/// state change into a separate panel-level implementation detail.
struct IslandAnimationProfile: Sendable {
    var open: Animation
    var close: Animation
    var pop: Animation
}

/// The edge treatment shared by the opened island's outer frame.
struct IslandBorderStyle: Sendable {
    var width: CGFloat
    var opacity: Double
    var isDouble: Bool
}

/// The sounds that belong to a visual language.
///
/// These are only the defaults a theme suggests — a sound the user picked for an
/// event still wins, so switching themes never throws away their choices.
///
/// Every name here is a macOS system sound. The sounds this look is reaching for
/// are someone else's work and cannot ship inside the app; these are the nearest
/// thing already on the machine, and the sound picker imports a real one.
enum IslandSoundProfile: Sendable {
    case standard
    case sao

    func soundName(for event: NotificationSoundEvent) -> String {
        switch self {
        case .standard:
            return "Bottle"
        case .sao:
            // Crystalline over percussive. Glass for the two moments that ask
            // something of you, Tink for the ones that only report.
            switch event {
            case .approvalNeeded, .answerNeeded: return "Glass"
            case .taskComplete: return "Hero"
            case .sessionStart, .contextLimit, .usageAlmostFull: return "Tink"
            }
        }
    }
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
    var animationProfile: IslandAnimationProfile { get }
    var borderStyle: IslandBorderStyle { get }
    /// Opacity of horizontal scanlines spaced three points apart; zero omits them.
    var scanlineIntensity: Double { get }
    var soundProfile: IslandSoundProfile { get }
}

enum IslandThemeID: String, CaseIterable, Identifiable, Sendable {
    /// The heads-up-display look: cool, angular, lit from within.
    case hud
    /// Cool, crystalline interface language with a more pronounced frame.
    case sao
    /// What the app looked like before themes existed: warm paper on black.
    case classic

    var id: String { rawValue }
    var labelKey: String { "settings.appearance.theme.\(rawValue)" }

    var theme: any IslandTheme {
        switch self {
        case .hud: HUDTheme()
        case .sao: SAOTheme()
        case .classic: ClassicTheme()
        }
    }
}

extension IslandTheme {
    /// The shape a card, button or badge should use at this corner size.
    func shape(cornerRadius: CGFloat) -> IslandPanelShape {
        IslandPanelShape(cornerRadius: cornerRadius, style: cornerStyle)
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
    // Timings measured off a 120fps capture of the reference product: the panel
    // grows for ~225ms with a decelerating curve and no overshoot, and collapses
    // in ~150ms. The previous 0.42s response felt soft and lagged the pointer;
    // 0.3s response at high damping lands on the same wall-clock duration.
    let animationProfile = IslandAnimationProfile(
        open: .spring(response: 0.3, dampingFraction: 0.9, blendDuration: 0),
        close: .smooth(duration: 0.15),
        pop: .spring(response: 0.3, dampingFraction: 0.5)
    )
    let borderStyle = IslandBorderStyle(width: 1, opacity: 0.07, isDouble: false)
    let scanlineIntensity = 0.0
    let soundProfile = IslandSoundProfile.standard
}

/// A crystalline HUD inspired by the cool, luminous language of Aincrad.
struct SAOTheme: IslandTheme {
    let id = IslandThemeID.sao

    // A bluer black preserves contrast against the physical notch while the
    // icy paper and cyan distinguish this from the more neutral HUD palette.
    let ink = Color(hex: 0x06101E)
    let paper = Color(hex: 0xE8F7FF)
    let accent = Color(hex: 0x54C8F2)

    let statusTints = IslandStatusTints(
        running: Color(hex: 0x54C8F2),
        // Warm waiting colours remain visually distinct for people who cannot
        // rely on the cold running tint alone.
        waitingForApproval: Color(hex: 0xFF9A58),
        waitingForAnswer: Color(hex: 0xFFD35A),
        completed: Color(hex: 0x63E6C4),
        waitingAggregate: Color(hex: 0xFFB86B),
        critical: Color(hex: 0xFF5275)
    )

    let cornerStyle = IslandCornerStyle.chamfered
    let glowRadius: CGFloat = 3.0
    let animationProfile = IslandAnimationProfile(
        open: .spring(response: 0.36, dampingFraction: 0.76, blendDuration: 0),
        close: .smooth(duration: 0.15),
        pop: .spring(response: 0.36, dampingFraction: 0.76)
    )
    let borderStyle = IslandBorderStyle(width: 1, opacity: 0.22, isDouble: true)
    let scanlineIntensity = 0.06
    let soundProfile = IslandSoundProfile.sao
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
    let animationProfile = IslandAnimationProfile(
        open: .spring(response: 0.3, dampingFraction: 0.9, blendDuration: 0),
        close: .smooth(duration: 0.15),
        pop: .spring(response: 0.3, dampingFraction: 0.5)
    )
    let borderStyle = IslandBorderStyle(width: 1, opacity: 0.07, isDouble: false)
    let scanlineIntensity = 0.0
    let soundProfile = IslandSoundProfile.standard
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
