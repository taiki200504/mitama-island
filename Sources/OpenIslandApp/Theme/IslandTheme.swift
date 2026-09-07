import SwiftUI

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

/// The sounds that belong to the SAO visual language.
///
/// These are only the defaults a theme suggests — a sound the user picked for an
/// event still wins, so this never throws away someone's own choice.
///
/// Every name here is a macOS system sound. The sounds this look is reaching for
/// are someone else's work and cannot ship inside the app; these are the nearest
/// thing already on the machine, and the sound picker imports a real one.
enum IslandSoundProfile: Sendable {
    case sao

    func soundName(for event: NotificationSoundEvent) -> String {
        // The macOS system chimes (Glass, Hero, Tink, Submarine) that this
        // switch used to return are replaced by cues synthesised for this app
        // — see docs/sound-design.md. `islandOpened` and the gesture-driven
        // open share one file: they are the same moment, just reached two
        // different ways, and a user who wants the gesture to stand out can
        // still give it its own sound from the settings pane.
        switch event {
        case .approvalNeeded, .answerNeeded, .eventStarting: return "ui-notify"
        case .taskComplete: return "ui-complete"
        case .sessionStart: return "ui-link"
        case .contextLimit, .usageAlmostFull, .warning: return "ui-warning"
        case .islandOpenedByGesture, .islandOpened: return "ui-open"
        case .islandClosed: return "ui-close"
        case .selection: return "ui-select"
        case .confirm: return "ui-confirm"
        case .approve: return "ui-approve"
        case .reject: return "ui-reject"
        case .timerFinished: return "ui-timer-end"
        case .lockScan: return "ui-lock-scan"
        case .unlock: return "ui-unlock"
        }
    }
}

/// A crystalline HUD inspired by the cool, luminous language of Aincrad.
///
/// The whole visual language, in one value. Read through `IslandThemes.current`
/// rather than an `Environment` value: the palette is also needed from
/// `ButtonStyle`, `Shape` and plain helper functions, none of which have an
/// environment to read from. Threading it through every one of those would be a
/// far larger change than this indirection.
struct SAOTheme: Sendable {
    /// The panel's own background. A bluer black preserves contrast against the
    /// physical notch while the icy paper and orange give the panel its edge.
    let ink = SAOGrammar.Palette.ink
    /// Text and anything drawn on top of `ink`.
    let paper = SAOGrammar.Palette.paper
    /// The one colour that means "this is the app talking".
    let accent = SAOGrammar.Palette.accentOrange

    let statusTints = IslandStatusTints(
        running: SAOGrammar.Palette.systemCyan,
        // Warm waiting colours remain visually distinct for people who cannot
        // rely on the cold running tint alone.
        waitingForApproval: SAOGrammar.Palette.statusYellow,
        waitingForAnswer: Color(hex: 0xFFD35A),
        completed: SAOGrammar.Palette.hpLimeEnd,
        waitingAggregate: SAOGrammar.Palette.accentAmber,
        critical: SAOGrammar.Palette.danger
    )

    /// How far a glow bleeds past its shape.
    let glowRadius: CGFloat = 3.0
    let animationProfile = IslandAnimationProfile(
        open: .spring(response: 0.36, dampingFraction: 0.76, blendDuration: 0),
        close: .smooth(duration: 0.15),
        pop: .spring(response: 0.36, dampingFraction: 0.76)
    )
    let soundProfile = IslandSoundProfile.sao

    /// The shape a card, button or badge should use at this corner size.
    func shape(cornerRadius: CGFloat) -> IslandPanelShape {
        IslandPanelShape(cornerRadius: cornerRadius)
    }
}

/// Shorthand so call sites read as `IslandThemes.current.accent`.
enum IslandThemes {
    static let current = SAOTheme()
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
