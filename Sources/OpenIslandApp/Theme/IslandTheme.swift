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
        // Crystalline over percussive. Glass for the two moments that ask
        // something of you, Tink for the ones that only report, and a low
        // sustained note for the gesture — it answers a deliberate pull of
        // the hand, so it should not sound like another notification.
        switch event {
        case .approvalNeeded, .answerNeeded: return "Glass"
        case .taskComplete: return "Hero"
        case .islandOpenedByGesture: return "Submarine"
        case .sessionStart, .contextLimit, .usageAlmostFull: return "Tink"
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
    /// physical notch while the icy paper and cyan give the panel its edge.
    let ink = Color(hex: 0x06101E)
    /// Text and anything drawn on top of `ink`.
    let paper = Color(hex: 0xE8F7FF)
    /// The one colour that means "this is the app talking".
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

    /// How far a glow bleeds past its shape.
    let glowRadius: CGFloat = 3.0
    let animationProfile = IslandAnimationProfile(
        open: .spring(response: 0.36, dampingFraction: 0.76, blendDuration: 0),
        close: .smooth(duration: 0.15),
        pop: .spring(response: 0.36, dampingFraction: 0.76)
    )
    /// Opacity of horizontal scanlines spaced three points apart.
    let scanlineIntensity = 0.06
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
