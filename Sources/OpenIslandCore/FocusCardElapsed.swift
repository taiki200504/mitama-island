import Foundation

/// How long ago an interruption was put down, in the coarsest unit that still
/// answers the question.
///
/// Free of `Date.now` so it can be checked at exact ages, the way
/// `CompletionDurationFormatter` is. The point of the line is "is this from
/// this morning or from Tuesday" — seconds have never been the answer, so
/// anything under a minute reads as just-now.
public enum FocusCardElapsed {
    public enum Unit: Equatable, Sendable {
        case justNow
        case minutes(Int)
        case hours(Int)
        case days(Int)
    }

    public static func unit(since savedAt: Date, now: Date = .now) -> Unit {
        let seconds = max(0, now.timeIntervalSince(savedAt))
        if seconds < 60 { return .justNow }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return .minutes(minutes) }
        let hours = minutes / 60
        if hours < 24 { return .hours(hours) }
        return .days(hours / 24)
    }
}
