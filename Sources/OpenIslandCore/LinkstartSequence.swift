import Foundation

/// One of the checks the sequence walks through before it lets you in.
public enum LinkstartSense: String, CaseIterable, Equatable, Sendable {
    case touch
    case sight
    case hearing
    case taste
    case smell

    /// Key into `Localizable.strings`.
    public var labelKey: String { "linkstart.sense.\(rawValue)" }
}

/// One of the sounds the boot sequence makes along the way.
public enum LinkstartCue: Equatable, Sendable {
    /// The light arriving, at the very start.
    case rise
    /// One per sense confirmed.
    case tick
    /// Everything passed; the checklist gives way to identity.
    case resolve
}

/// One colour of the calibration wash that runs between the opening burst
/// and the checklist: red, green, blue, then white — once, not a repeating
/// cycle, and slow enough to read as a colour wash rather than a strobe.
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

/// Where the boot sequence is at a given moment.
public enum LinkstartPhase: Equatable, Sendable {
    /// Before the light has arrived. Also where a clock that moved backwards
    /// lands, so the view always has a state to draw.
    case awakening
    /// Concentric rings pulsing outward.
    case rings
    /// The rays bursting open, continuing after the rings have landed.
    case rays
    /// The colour-calibration flash, this many steps into its sequence.
    case calibration(step: Int)
    /// Running the senses, with this many already confirmed.
    case senses(checked: Int)
    case language
    case identity
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

    /// The concentric rings pulsing outward from the centre.
    public static let ringsDuration: TimeInterval = 1.20
    /// The rays start mid-way through the rings, and outlast them.
    public static let raysStart: TimeInterval = 0.60
    public static let raysDuration: TimeInterval = 1.40
    /// The colour-calibration flash, once the rays have settled.
    public static let calibrationDuration: TimeInterval = 1.00
    /// How long each sense takes to confirm.
    public static let perSenseDuration: TimeInterval = 0.5
    public static let languageDuration: TimeInterval = 0.9
    public static let identityDuration: TimeInterval = 1.6
    public static let fadeDuration: TimeInterval = 0.80

    public static var raysEnd: TimeInterval { raysStart + raysDuration }

    public static var sensesDuration: TimeInterval {
        perSenseDuration * Double(senses.count)
    }

    public static var sensesStart: TimeInterval { raysEnd + calibrationDuration }
    public static var languageStart: TimeInterval { sensesStart + sensesDuration }
    public static var identityStart: TimeInterval { languageStart + languageDuration }
    public static var fadeStart: TimeInterval { identityStart + identityDuration }

    /// Total run time. After this the overlay dismisses itself.
    public static var duration: TimeInterval { fadeStart + fadeDuration }

    public static func phase(at elapsed: TimeInterval) -> LinkstartPhase {
        // Negative time can only come from a clock that moved. Treat it as the
        // beginning rather than as an error the view would have to render.
        guard elapsed > 0 else { return .awakening }
        if elapsed < ringsDuration { return .rings }
        if elapsed < raysEnd { return .rays }
        if elapsed < sensesStart { return .calibration(step: calibrationStepIndex(at: elapsed)) }

        let intoSenses = elapsed - sensesStart
        if intoSenses < sensesDuration {
            let checked = Int(intoSenses / perSenseDuration)
            return .senses(checked: min(checked, senses.count))
        }

        if elapsed < identityStart { return .language }
        if elapsed < fadeStart { return .identity }
        if elapsed < duration { return .fade }
        return .complete
    }

    /// How many senses are lit, at any phase — the view draws the same list the
    /// whole way through, so it needs an answer even after the checks are done.
    public static func confirmedSenseCount(at elapsed: TimeInterval) -> Int {
        switch phase(at: elapsed) {
        case .awakening, .rings, .rays, .calibration:
            0
        case let .senses(checked):
            checked
        case .language, .identity, .fade, .complete:
            senses.count
        }
    }

    /// When each sound plays, derived from the same durations the view draws
    /// from so the soundtrack can never drift out of step with the checklist:
    /// the rise as the light arrives, a tick as each sense starts confirming,
    /// and the resolve as the checklist gives way to identity.
    public static var cueSchedule: [(at: TimeInterval, cue: LinkstartCue)] {
        var schedule: [(at: TimeInterval, cue: LinkstartCue)] = [(0, .rise)]
        for index in senses.indices {
            schedule.append((sensesStart + Double(index) * perSenseDuration, .tick))
        }
        schedule.append((identityStart, .resolve))
        return schedule
    }

    // MARK: - Rings and rays

    /// Progress (0…1, eased) of each of 5 rings. Ring `i` lags the leading
    /// ring by `0.12 * i` of the rings' own duration, so they read as catching
    /// up to each other rather than moving as one rigid disc — the same lag
    /// `SAORing.radii` applies to the radius itself, kept here as a pure,
    /// testable value for the choreography rather than the geometry.
    public static func ringProgress(at elapsed: TimeInterval) -> [Double] {
        let base = elapsed / ringsDuration
        return (0..<5).map { index in easeOut(base - 0.12 * Double(index)) }
    }

    /// Progress (0…1, eased) of the ray burst.
    public static func rayProgress(at elapsed: TimeInterval) -> Double {
        easeOut((elapsed - raysStart) / raysDuration)
    }

    // MARK: - Calibration

    private static let calibrationSteps: [CalibrationStep] = [.red, .green, .blue, .white]
    /// The strongest the wash ever gets — capped well under full opacity so
    /// even the moment it lands is a wash, not a flash.
    private static let calibrationMaxOpacity: Double = 0.35
    /// Half the width of the handoff around each colour change: a colour
    /// starts giving way to the next 0.05s before its nominal boundary and
    /// finishes 0.05s after, so no change is ever a hard cut.
    private static let calibrationCrossfadeHalfWidth: TimeInterval = 0.05

    /// Where red gives way to green, green to blue, and blue to white — red,
    /// green and blue each hold 0.30s (≈1 colour change per second, well
    /// under the ~3Hz photosensitivity guideline) and white closes the
    /// pattern out at 0.10s, for the `calibrationDuration` of 1.00s this adds
    /// up to. Each is a single offset from `raysEnd` rather than a running
    /// sum — repeated addition drifts by a ULP or two, which is enough to put
    /// an exact boundary on the wrong side of a test's expectation.
    private static let calibrationTransitionTimes: [TimeInterval] = [
        raysEnd + 0.30, raysEnd + 0.60, raysEnd + 0.90,
    ]

    /// The colour(s) on screen during the calibration wash: one frame at full
    /// strength while holding, two — one fading out, one in — while handing
    /// off to the next colour. Empty outside the wash entirely, including its
    /// own tail once white has finished and nothing is left to show before
    /// the senses begin.
    public static func calibrationFrames(at elapsed: TimeInterval) -> [CalibrationFrame] {
        guard elapsed >= raysEnd, elapsed < sensesStart else { return [] }

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
        let t = min(max((elapsed - fadeStart) / fadeDuration, 0), 1)
        return 1 - t
    }

    private static func easeOut(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        return 1 - pow(1 - clamped, 3)
    }
}
