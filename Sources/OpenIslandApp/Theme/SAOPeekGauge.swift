import SwiftUI
import OpenIslandCore

/// Turns an `IslandClosedBody` into what `SAOPeekGaugeView` draws: a label, an
/// elapsed/upcoming reading, a gauge fraction and tint, and whether the
/// trailing count is "still waiting" (breathes) or just "ahead" (dim).
///
/// Deliberately fixed-English, the same choice the old peek band made for the
/// agent name: this is a HUD readout in the crystal-HUD grammar's own display
/// face, not a piece of localized UI copy, and Rajdhani has no glyphs to
/// localize it into anyway.
enum SAOPeekGauge {
    /// `justNow` → full and calm; the longer something waits the lower the
    /// gauge runs, until an hour in it's a thin red sliver. `m < 10` still
    /// reads as "fine", past that it's read as overdue.
    static func level(elapsed: IslandPeekBand.Elapsed) -> (fraction: Double, tint: Color) {
        switch elapsed {
        case .justNow:
            return (1.0, SAOGrammar.Palette.hpLimeEnd)
        case .minutes(let minutes):
            let fraction = max(0.2, 1 - Double(minutes) / 30)
            let tint = minutes < 10 ? SAOGrammar.Palette.hpLimeEnd : SAOGrammar.Palette.accentOrange
            return (fraction, tint)
        case .hours:
            return (0.15, SAOGrammar.Palette.danger)
        }
    }

    /// The inverse of `level(elapsed:)`: a calendar entry that is far away
    /// starts near-empty and fills in as the start time approaches, capped at
    /// an hour out so the gauge doesn't sit visibly empty all morning for a
    /// 9am meeting.
    static func levelForUpcoming(minutesUntil: Int) -> (fraction: Double, tint: Color) {
        let fraction = 1 - Double(min(minutesUntil, 60)) / 60
        return (fraction, SAOGrammar.Palette.systemCyan)
    }

    /// A mitama alert nobody has answered. Full and red, and the view blinks
    /// it rather than trusting a static red bar to read as "act on this".
    static let urgent: (fraction: Double, tint: Color) = (1.0, SAOGrammar.Palette.danger)

    static func label(for body: IslandClosedBody) -> String {
        switch body {
        case .urgent(let peek), .waiting(let peek):
            peek.agent
        case .eventStarted(_, let startedAt, _):
            clockFormatter.string(from: startedAt)
        case .nextEvent(let band):
            clockFormatter.string(from: band.startsAt)
        }
    }

    static func elapsedText(for body: IslandClosedBody) -> String {
        switch body {
        case .urgent(let peek), .waiting(let peek):
            text(for: peek.elapsed)
        case .eventStarted:
            "STARTED"
        case .nextEvent(let band):
            "IN \(band.minutesUntil)M"
        }
    }

    static func othersCount(for body: IslandClosedBody) -> Int {
        switch body {
        case .urgent(let peek), .waiting(let peek):
            peek.othersWaiting
        case .eventStarted:
            0
        case .nextEvent(let band):
            band.othersAhead
        }
    }

    /// Whether the trailing count is still-waiting (breathes statusYellow) or
    /// just ahead-in-line (a dim, static count) — the shelf's own idle tone.
    static func tailIsWaiting(for body: IslandClosedBody) -> Bool {
        switch body {
        case .urgent, .waiting:
            true
        case .eventStarted, .nextEvent:
            false
        }
    }

    static func gaugeLevel(for body: IslandClosedBody) -> (fraction: Double, tint: Color) {
        switch body {
        case .urgent:
            urgent
        case .waiting(let peek):
            level(elapsed: peek.elapsed)
        case .eventStarted:
            (1.0, SAOGrammar.Palette.accentOrange)
        case .nextEvent(let band):
            levelForUpcoming(minutesUntil: band.minutesUntil)
        }
    }

    static func isUrgent(_ body: IslandClosedBody) -> Bool {
        if case .urgent = body { return true }
        return false
    }

    /// `justNow` / `2m` / `1h` — no seconds, matching the pill's once-a-minute
    /// redraw budget.
    static func text(for elapsed: IslandPeekBand.Elapsed) -> String {
        switch elapsed {
        case .justNow:
            "NOW"
        case .minutes(let minutes):
            "\(minutes)M"
        case .hours(let hours):
            "\(hours)H"
        }
    }

    /// Fixed 24-hour, so the label's width never changes over the day. A
    /// locale that formats 9am as "9:00 AM" would make the pill breathe on
    /// the hour.
    static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
