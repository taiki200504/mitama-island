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

/// Where the boot sequence is at a given moment.
public enum LinkstartPhase: Equatable, Sendable {
    /// The light is arriving. Nothing has been checked yet.
    case awakening
    /// Running the senses, with this many already confirmed.
    case senses(checked: Int)
    case language
    case identity
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

    /// The light before the first check.
    public static let awakeningDuration: TimeInterval = 1.2
    /// How long each sense takes to confirm.
    public static let perSenseDuration: TimeInterval = 0.5
    public static let languageDuration: TimeInterval = 0.9
    public static let identityDuration: TimeInterval = 1.6

    public static var sensesDuration: TimeInterval {
        perSenseDuration * Double(senses.count)
    }

    /// Total run time. After this the overlay dismisses itself.
    public static var duration: TimeInterval {
        awakeningDuration + sensesDuration + languageDuration + identityDuration
    }

    public static func phase(at elapsed: TimeInterval) -> LinkstartPhase {
        // Negative time can only come from a clock that moved. Treat it as the
        // beginning rather than as an error the view would have to render.
        guard elapsed > 0 else { return .awakening }
        if elapsed < awakeningDuration { return .awakening }

        let intoSenses = elapsed - awakeningDuration
        if intoSenses < sensesDuration {
            let checked = Int(intoSenses / perSenseDuration)
            return .senses(checked: min(checked, senses.count))
        }

        let intoLanguage = intoSenses - sensesDuration
        if intoLanguage < languageDuration { return .language }

        let intoIdentity = intoLanguage - languageDuration
        if intoIdentity < identityDuration { return .identity }

        return .complete
    }

    /// How many senses are lit, at any phase — the view draws the same list the
    /// whole way through, so it needs an answer even after the checks are done.
    public static func confirmedSenseCount(at elapsed: TimeInterval) -> Int {
        switch phase(at: elapsed) {
        case .awakening: 0
        case let .senses(checked): checked
        case .language, .identity, .complete: senses.count
        }
    }
}
