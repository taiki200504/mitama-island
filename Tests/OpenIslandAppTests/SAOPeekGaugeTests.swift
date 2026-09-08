import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
@Suite("SAO peek gauge")
struct SAOPeekGaugeTests {
    @Test("justNow is full and lime")
    func justNow() {
        let level = SAOPeekGauge.level(elapsed: .justNow)
        #expect(level.fraction == 1.0)
        #expect(level.tint == SAOGrammar.Palette.hpLimeEnd)
    }

    @Test("9 minutes is still lime, just under the fraction from the raw formula")
    func nineMinutes() {
        let level = SAOPeekGauge.level(elapsed: .minutes(9))
        #expect(abs(level.fraction - 0.7) < 0.0001)
        #expect(level.tint == SAOGrammar.Palette.hpLimeEnd)
    }

    @Test("10 minutes turns the gauge orange, at the boundary the formula names")
    func tenMinutes() {
        let level = SAOPeekGauge.level(elapsed: .minutes(10))
        #expect(abs(level.fraction - (1 - 10.0 / 30.0)) < 0.0001)
        #expect(level.tint == SAOGrammar.Palette.accentOrange)
    }

    @Test("30 minutes floors the fraction at 0.2 rather than letting it hit zero")
    func thirtyMinutes() {
        let level = SAOPeekGauge.level(elapsed: .minutes(30))
        #expect(level.fraction == 0.2)
        #expect(level.tint == SAOGrammar.Palette.accentOrange)
    }

    @Test("An hour or more is a thin red sliver")
    func oneHour() {
        let level = SAOPeekGauge.level(elapsed: .hours(1))
        #expect(level.fraction == 0.15)
        #expect(level.tint == SAOGrammar.Palette.danger)
    }

    @Test("Upcoming fills toward full as the start time approaches")
    func upcomingFillsIn() {
        #expect(abs(SAOPeekGauge.levelForUpcoming(minutesUntil: 60).fraction - 0.0) < 0.0001)
        #expect(abs(SAOPeekGauge.levelForUpcoming(minutesUntil: 30).fraction - 0.5) < 0.0001)
        #expect(SAOPeekGauge.levelForUpcoming(minutesUntil: 0).fraction == 1.0)
    }

    @Test("Upcoming caps at an hour out — further away reads the same as an hour")
    func upcomingCapsAtAnHour() {
        let farAway = SAOPeekGauge.levelForUpcoming(minutesUntil: 480)
        let anHourOut = SAOPeekGauge.levelForUpcoming(minutesUntil: 60)
        #expect(farAway.fraction == anHourOut.fraction)
    }

    @Test("Urgent is always full and red")
    func urgentConstant() {
        #expect(SAOPeekGauge.urgent.fraction == 1.0)
        #expect(SAOPeekGauge.urgent.tint == SAOGrammar.Palette.danger)
    }

    private func peekContent(elapsed: IslandPeekBand.Elapsed, others: Int = 0) -> IslandPeekBand.Content {
        IslandPeekBand.Content(agent: "CODEX", subject: .session(.waitingForApproval), elapsed: elapsed, othersWaiting: others)
    }

    @Test("A waiting body's gauge matches level(elapsed:)")
    func waitingBodyUsesElapsedLevel() {
        let body = IslandClosedBody.waiting(peekContent(elapsed: .minutes(5)))
        let level = SAOPeekGauge.gaugeLevel(for: body)
        #expect(level.fraction == SAOPeekGauge.level(elapsed: .minutes(5)).fraction)
        #expect(!SAOPeekGauge.isUrgent(body))
        #expect(SAOPeekGauge.tailIsWaiting(for: body))
    }

    @Test("An urgent body's gauge is the fixed urgent level and is marked urgent")
    func urgentBodyUsesUrgentLevel() {
        let body = IslandClosedBody.urgent(peekContent(elapsed: .justNow))
        let level = SAOPeekGauge.gaugeLevel(for: body)
        #expect(level.fraction == SAOPeekGauge.urgent.fraction)
        #expect(level.tint == SAOPeekGauge.urgent.tint)
        #expect(SAOPeekGauge.isUrgent(body))
    }

    @Test("A next-event body's gauge matches levelForUpcoming and is never marked waiting")
    func nextEventBodyUsesUpcomingLevel() {
        let band = UpcomingCalendarEvent.Band(title: "Standup", startsAt: .now, minutesUntil: 20, othersAhead: 1)
        let body = IslandClosedBody.nextEvent(band)
        let level = SAOPeekGauge.gaugeLevel(for: body)
        #expect(abs(level.fraction - SAOPeekGauge.levelForUpcoming(minutesUntil: 20).fraction) < 0.0001)
        #expect(SAOPeekGauge.othersCount(for: body) == 1)
        #expect(!SAOPeekGauge.tailIsWaiting(for: body))
    }

    @Test("Elapsed text has no seconds and no localization")
    func elapsedTextTokens() {
        #expect(SAOPeekGauge.text(for: .justNow) == "NOW")
        #expect(SAOPeekGauge.text(for: .minutes(7)) == "7M")
        #expect(SAOPeekGauge.text(for: .hours(3)) == "3H")
    }

    @Test("An event-started body reads NOW with the start–end range, and carries the title")
    func eventStartedReadsNowWithTheTimeRange() {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15 00:00:00 UTC
        let body = IslandClosedBody.eventStarted(
            title: "Design sync",
            startedAt: startedAt,
            endsAt: startedAt.addingTimeInterval(1_800),
            url: nil
        )
        #expect(SAOPeekGauge.label(for: body) == "NOW")
        #expect(SAOPeekGauge.elapsedText(for: body).contains("–"))
        #expect(SAOPeekGauge.eventTitle(for: body) == "Design sync")
        #expect(SAOPeekGauge.othersCount(for: body) == 0)
        #expect(!SAOPeekGauge.tailIsWaiting(for: body))
    }

    @Test("Only an event-started body carries a title")
    func onlyEventStartedCarriesATitle() {
        let waiting = IslandClosedBody.waiting(peekContent(elapsed: .minutes(1)))
        #expect(SAOPeekGauge.eventTitle(for: waiting) == nil)

        let band = UpcomingCalendarEvent.Band(title: "Standup", startsAt: .now, minutesUntil: 5, othersAhead: 0)
        #expect(SAOPeekGauge.eventTitle(for: .nextEvent(band)) == nil)
    }
}
