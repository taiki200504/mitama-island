import Foundation

/// One of the checks the sequence walks through before it lets you in.
public enum LinkstartSense: String, CaseIterable, Equatable, Sendable {
    case touch
    case sight
    case hearing
    case taste
    case smell

}

/// One of the sounds the boot sequence makes along the way.
public enum LinkstartCue: Equatable, Sendable {
    /// The light arriving, at the very start.
    case rise
    /// The dive into the tunnel of light.
    case warp
    /// The white-out at the far end of the tunnel.
    case flash
    /// One per sense confirmed.
    case tick
    /// Everything passed; the checklist gives way to identity.
    case resolve
    /// Dive at the end, approaching portal.
    case dive
}

/// One colour of the calibration wash that runs between the white-out and
/// the checklist: red, green, blue, then white — once, not a repeating cycle,
/// and slow enough to read as a colour wash rather than a strobe.
public enum CalibrationStep: Equatable, Sendable {
    case red
    case green
    case blue
    case white
}

/// A colour and how strongly it's showing during the calibration wash.
/// `calibrationFrames(at:)` returns two of these during a handoff between
/// colours — one fading out, one fading in — so the view can draw a
/// straight opacity blend instead of a hard colour cut.
public struct CalibrationFrame: Equatable, Sendable {
    public let step: CalibrationStep
    public let opacity: Double
}

/// One line of light in the tunnel, in screen-independent units: `angle` in
/// radians from the centre, `inner`/`outer` as fractions of half the screen's
/// diagonal, so the same frame fills a laptop and a 6K display alike.
public struct LinkstartStreak: Equatable, Sendable {
    public let angle: Double
    public let inner: Double
    public let outer: Double
    /// 0…1 around the colour wheel.
    public let hue: Double
    public let opacity: Double
    /// Relative thickness, growing as the streak nears the viewer.
    public let width: Double
}

/// How the title card sits at a moment: its size, how visible it is, and how
/// far its red and cyan copies are pulled apart (1 = fully split, 0 = one image).
public struct LinkstartTitleFrame: Equatable, Sendable {
    public let scale: Double
    public let opacity: Double
    public let split: Double
}

/// Where the boot sequence is at a given moment.
public enum LinkstartPhase: Equatable, Sendable {
    /// Before the light has arrived. Also where a clock that moved backwards
    /// lands, so the view always has a state to draw.
    case awakening
    /// The title slams in and the shockwave rings go out.
    case ignition
    /// Diving through the tunnel of light, faster and faster.
    case warp
    /// The white-out at the tunnel's end.
    case flash
    /// The colour-calibration wash, this many steps into its sequence.
    case calibration(step: Int)
    /// Running the senses, with this many already confirmed.
    case senses(checked: Int)
    /// Column of green check circles for confirmed senses.
    case sensesCheck
    /// Language selection button.
    case languageSelect
    /// Login panel with account and password fields.
    case loginPanel
    /// Confirmation dialog.
    case confirmationDialog
    /// Welcome text display.
    case welcome
    /// Blue dive at the end.
    case dive
    /// The whole overlay dissolving, on the way to `.complete`.
    case fade
    /// Everything passed; the overlay can leave.
    case complete
}

/// The timing of the login sequence, as a pure function of elapsed time.
///
/// Kept away from the view so the choreography can be tested without a screen,
/// and so a dropped frame changes how it *looks* but never where it *is*: the
/// view asks what time it is rather than counting steps it has drawn.
public enum LinkstartSequence: Sendable {
    public static let senses = LinkstartSense.allCases

    // Every number below is the reference recording's own, measured from it
    // frame by frame (scene changes at 5 fps). They are not a designer's
    // rhythm: an installed soundtrack plays straight through, so the picture
    // has to sit on the audio's beats or the two drift apart within a second.
    //
    //   0.0–1.4  dark, the spoken trigger
    //   1.4–3.5  white, a speck at centre growing
    //   3.5–5.0  the wedge tunnel
    //   5.0–5.8  white-out
    //   5.7–8.2  the sense discs passing the camera, one confirming at a time
    //   8.2–8.85 the five marks turning green and scattering
    //   9.35–10.3 language
    //  10.4–11.8 sign-in
    //  12.0–13.55 the confirmation
    //  13.6–16.6 welcome
    //  16.6–18.4 the dive
    //  18.4–19.0 white-out, end

    /// Dark, before anything is drawn.
    public static let awakeningDuration: TimeInterval = 1.4
    /// White, with the speck at the centre growing.
    public static let ignitionDuration: TimeInterval = 2.1
    /// The shockwave rings, overlapping the start of the dive.
    public static let ringsDuration: TimeInterval = 1.20
    /// The wedge tunnel.
    public static let warpDuration: TimeInterval = 1.5
    /// The white-out between the tunnel and the interface.
    public static let flashDuration: TimeInterval = 0.8
    /// The sense discs passing the camera, one confirming at a time.
    public static let calibrationDuration: TimeInterval = 2.3
    /// The five marks turning green at the right edge, then scattering.
    public static let sensesCheckDuration: TimeInterval = 0.75
    /// Language selection button.
    public static let languageSelectDuration: TimeInterval = 0.95
    /// Sign-in panel.
    public static let loginPanelDuration: TimeInterval = 1.4
    /// Confirmation dialog.
    public static let confirmationDialogDuration: TimeInterval = 1.55

    // The reference leaves the screen plain white between these screens —
    // after the checks, and again between sign-in and the confirmation. They
    // are part of its rhythm, so they are timed rather than smoothed over.
    /// White, between the checks and the language button.
    public static let afterChecksGap: TimeInterval = 0.5
    /// White, between sign-in and the confirmation.
    public static let afterLoginGap: TimeInterval = 0.2
    /// Welcome text.
    public static let welcomeDuration: TimeInterval = 3.0
    /// The blue dive.
    public static let diveDuration: TimeInterval = 1.8
    /// Final fade-out.
    public static let finalFadeDuration: TimeInterval = 0.64

    public static var ignitionStart: TimeInterval { awakeningDuration }
    public static var warpStart: TimeInterval { ignitionStart + ignitionDuration }
    public static var flashStart: TimeInterval { warpStart + warpDuration }
    public static var warpEnd: TimeInterval { flashStart + flashDuration }
    public static var calibrationStart: TimeInterval { warpEnd }

    public static var sensesCheckStart: TimeInterval { calibrationStart + calibrationDuration }
    public static var languageSelectStart: TimeInterval {
        sensesCheckStart + sensesCheckDuration + afterChecksGap
    }
    public static var loginPanelStart: TimeInterval {
        languageSelectStart + languageSelectDuration + 0.1
    }
    public static var confirmationDialogStart: TimeInterval {
        loginPanelStart + loginPanelDuration + afterLoginGap
    }
    public static var welcomeStart: TimeInterval {
        confirmationDialogStart + confirmationDialogDuration + 0.05
    }
    public static var diveStart: TimeInterval { welcomeStart + welcomeDuration }
    public static var fadeStart: TimeInterval { diveStart + diveDuration }

    /// Total run time. After this the overlay dismisses itself.
    public static var duration: TimeInterval { fadeStart + finalFadeDuration }

    public static func phase(at elapsed: TimeInterval) -> LinkstartPhase {
        // Negative time can only come from a clock that moved. Treat it as the
        // beginning rather than as an error the view would have to render.
        guard elapsed > 0 else { return .awakening }
        if elapsed < ignitionStart { return .awakening }
        if elapsed < warpStart { return .ignition }
        if elapsed < flashStart { return .warp }
        if elapsed < warpEnd { return .flash }
        // 五感は calibration の時間帯のうちに 1 つずつ確定する。ここを
        // `.calibration(step: 0)` で潰していたせいで確認済みの数がいつまでも
        // 0 のままになり、音だけ進んで画が動かなかった。
        if elapsed < sensesCheckStart {
            return .senses(checked: LinkstartSenses.confirmedCount(at: elapsed))
        }

        if elapsed < languageSelectStart { return .sensesCheck }
        if elapsed < loginPanelStart { return .languageSelect }
        if elapsed < confirmationDialogStart { return .loginPanel }
        if elapsed < welcomeStart { return .confirmationDialog }
        if elapsed < diveStart { return .welcome }
        if elapsed < fadeStart { return .dive }
        if elapsed < duration { return .fade }
        return .complete
    }

    /// How many senses are lit, at any phase — the view draws the same list the
    /// whole way through, so it needs an answer even after the checks are done.
    public static func confirmedSenseCount(at elapsed: TimeInterval) -> Int {
        switch phase(at: elapsed) {
        case .awakening, .ignition, .warp, .flash, .calibration:
            0
        case let .senses(checked):
            checked
        case .sensesCheck, .languageSelect, .loginPanel, .confirmationDialog, .welcome, .dive, .fade, .complete:
            senses.count
        }
    }

    /// When each sound plays, derived from the same durations the view draws
    /// from so the soundtrack can never drift out of step with the picture.
    public static var cueSchedule: [(at: TimeInterval, cue: LinkstartCue)] {
        var schedule: [(at: TimeInterval, cue: LinkstartCue)] = [
            (0, .rise),
            (warpStart, .warp),
            (flashStart, .flash),
        ]
        // 五感が確定する瞬間。等間隔ではなく、参照映像で実際にプレートが
        // OK へ反転する時刻に置く（本人の音源がある時はこのキューは鳴らない
        // が、無い環境ではこれが画と音を合わせる唯一の手がかりになる）。
        for beat in LinkstartSenses.beats {
            schedule.append((beat.confirms, .tick))
        }
        // The interface settling, then the dive out of it.
        schedule.append((sensesCheckStart, .resolve))
        schedule.append((diveStart, .dive))
        return schedule
    }

    // MARK: - Ignition

    /// Progress (0…1, eased) of each of 5 rings. Ring `i` lags the leading
    /// ring by `0.12 * i` of the rings' own duration, so they read as catching
    /// up to each other rather than moving as one rigid disc.
    public static func ringProgress(at elapsed: TimeInterval) -> [Double] {
        let base = elapsed / ringsDuration
        return (0..<5).map { index in easeOut(base - 0.12 * Double(index)) }
    }

    /// The title card: slams in from 1.6× with its colour copies split, holds
    /// as the dive begins, then flies past the viewer into the tunnel.
    /// Nothing once it has gone — the checklist's own title takes over later.
    public static func titleSlam(at elapsed: TimeInterval) -> LinkstartTitleFrame {
        guard elapsed > 0 else { return LinkstartTitleFrame(scale: 1.6, opacity: 0, split: 1) }
        let slam = easeOut(elapsed / 0.3)
        let opacityIn = clamp01(elapsed / 0.12)
        let split = 1 - easeOut(elapsed / 0.45)

        let flyStart = warpStart + 0.4
        let fly = clamp01((elapsed - flyStart) / 0.6)
        let scale = (1.6 - 0.6 * slam) * (1 + 1.6 * fly * fly)
        return LinkstartTitleFrame(scale: scale, opacity: opacityIn * (1 - fly), split: max(split, fly * 0.6))
    }

    // MARK: - Warp

    /// How many lines of light the tunnel draws.
    public static let streakCount = 160

    /// How strongly the tunnel shows: up over its first 0.3s, full until the
    /// white-out swallows it.
    public static func warpIntensity(at elapsed: TimeInterval) -> Double {
        guard elapsed >= warpStart, elapsed < warpEnd else { return 0 }
        return easeOut((elapsed - warpStart) / 0.3)
    }

    /// How fast the dive is going, 0 at the mouth of the tunnel to 1 at its end.
    public static func warpSpeed(at elapsed: TimeInterval) -> Double {
        clamp01((elapsed - warpStart) / warpDuration)
    }

    /// Every line of light in the tunnel at this moment. Deterministic — the
    /// same elapsed time always draws the same frame — so the harness can pin
    /// a screenshot and a dropped frame never reshuffles the tunnel.
    public static func streaks(at elapsed: TimeInterval) -> [LinkstartStreak] {
        let intensity = warpIntensity(at: elapsed)
        guard intensity > 0 else { return [] }

        let tau = elapsed - warpStart
        // Distance travelled: accelerating, in tunnel-lengths.
        let travelled = 0.35 * tau + 0.45 * tau * tau
        let speed = warpSpeed(at: elapsed)

        return (0..<streakCount).map { index in
            let angle = unitHash(index, salt: 1) * 2 * .pi
            let offset = unitHash(index, salt: 2)
            let pace = 0.7 + 0.6 * unitHash(index, salt: 3)
            // Most of the tunnel is blue-white; about a third takes the rest
            // of the spectrum, which is what makes it read as a rainbow rush
            // rather than a starfield.
            let hueSeed = unitHash(index, salt: 4)
            let hue = hueSeed < 0.65 ? 0.52 + 0.14 * (hueSeed / 0.65) : (hueSeed - 0.65) / 0.35

            let depth = fract(offset + travelled * pace)
            let tail = max(0, depth - (0.03 + 0.14 * speed))
            let nearCentreFade = clamp01(depth / 0.18)

            return LinkstartStreak(
                angle: angle,
                inner: perspective(tail),
                outer: perspective(depth),
                hue: hue,
                opacity: intensity * nearCentreFade,
                width: 0.4 + 1.8 * depth
            )
        }
    }

    /// The glow at the tunnel's vanishing point, brightening as the dive speeds up.
    public static func coreGlow(at elapsed: TimeInterval) -> Double {
        warpIntensity(at: elapsed) * (0.25 + 0.75 * warpSpeed(at: elapsed))
    }

    // MARK: - Flash

    /// The strongest the white-out gets — bright enough to read as arriving
    /// somewhere, never a full-white frame.
    public static let flashPeakOpacity: Double = 0.85


    public static func flashOpacity(at elapsed: TimeInterval) -> Double {
        let rise = 0.12
        let start = flashStart - rise
        guard elapsed > start, elapsed < warpEnd else { return 0 }
        if elapsed < flashStart {
            return flashPeakOpacity * (elapsed - start) / rise
        }
        return flashPeakOpacity * (1 - easeOut((elapsed - flashStart) / flashDuration))
    }

    // MARK: - Checklist


    /// The synchronisation rate shown under the checklist, 0…100: climbs
    /// from the calibration wash to full as the senses check completes.
    public static func syncRate(at elapsed: TimeInterval) -> Int {
        let progress = clamp01((elapsed - calibrationStart) / (sensesCheckStart - calibrationStart))
        return Int((easeInOut(progress) * 100).rounded())
    }

    // MARK: - Calibration

    private static let calibrationSteps: [CalibrationStep] = [.red, .green, .blue, .white]
    /// The strongest the wash ever gets — capped well under full opacity so
    /// even the moment it lands is a wash, not a flash.
    private static let calibrationMaxOpacity: Double = 0.35
    /// Half the width of the handoff around each colour change.
    private static let calibrationCrossfadeHalfWidth: TimeInterval = 0.05

    /// Where red gives way to green, green to blue, and blue to white — each
    /// held 0.30s (≈1 change per second, well under the ~3Hz photosensitivity
    /// guideline), white closing out at 0.10s. Each is a single offset from
    /// `calibrationStart` rather than a running sum, so no boundary drifts.
    private static var calibrationTransitionTimes: [TimeInterval] {
        [calibrationStart + 0.30, calibrationStart + 0.60, calibrationStart + 0.90]
    }

    /// The colour(s) on screen during the calibration wash: one frame at full
    /// strength while holding, two while handing off. Empty outside the wash.
    public static func calibrationFrames(at elapsed: TimeInterval) -> [CalibrationFrame] {
        guard elapsed >= calibrationStart, elapsed < sensesCheckStart else { return [] }

        for (index, boundary) in calibrationTransitionTimes.enumerated() {
            let windowStart = boundary - calibrationCrossfadeHalfWidth
            let windowEnd = boundary + calibrationCrossfadeHalfWidth
            guard elapsed >= windowStart, elapsed < windowEnd else { continue }
            let progress = (elapsed - windowStart) / (calibrationCrossfadeHalfWidth * 2)
            return [
                CalibrationFrame(step: calibrationSteps[index], opacity: calibrationMaxOpacity * (1 - progress)),
                CalibrationFrame(step: calibrationSteps[index + 1], opacity: calibrationMaxOpacity * progress),
            ]
        }

        return [CalibrationFrame(step: calibrationSteps[calibrationStepIndex(at: elapsed)], opacity: calibrationMaxOpacity)]
    }

    private static func calibrationStepIndex(at elapsed: TimeInterval) -> Int {
        calibrationTransitionTimes.firstIndex(where: { elapsed < $0 }) ?? calibrationSteps.count - 1
    }

    // MARK: - Fade

    /// Overlay opacity during the closing fade: 1 until it starts, ramping
    /// down to 0 by the time the sequence completes.
    public static func fadeOpacity(at elapsed: TimeInterval) -> Double {
        guard elapsed > fadeStart else { return 1 }
        return 1 - clamp01((elapsed - fadeStart) / finalFadeDuration)
    }

    // MARK: - Maths

    /// Also used by the view for its own cross-fades.
    public static func clamp01(_ t: Double) -> Double { min(max(t, 0), 1) }

    private static func easeOut(_ t: Double) -> Double {
        1 - pow(1 - clamp01(t), 3)
    }

    private static func easeInOut(_ t: Double) -> Double {
        let x = clamp01(t)
        return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    private static func fract(_ x: Double) -> Double { x - x.rounded(.down) }

    /// Depth to on-screen radius: slow near the vanishing point, rushing past
    /// at the edges, and a little beyond them so streaks leave the screen.
    private static func perspective(_ depth: Double) -> Double {
        1.15 * pow(depth, 2.4)
    }

    /// A stable 0..<1 value per streak (SplitMix64), so the tunnel is the same
    /// every run without storing a table.
    private static func unitHash(_ index: Int, salt: UInt64) -> Double {
        var z = UInt64(truncatingIfNeeded: index) &* 0x9E37_79B9_7F4A_7C15 &+ salt &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
