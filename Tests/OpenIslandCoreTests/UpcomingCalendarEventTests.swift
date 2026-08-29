import Foundation
import Testing
@testable import OpenIslandCore

@Suite struct UpcomingCalendarEventTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(_ title: String, inMinutes: Double, allDay: Bool = false) -> UpcomingCalendarEvent.Event {
        .init(title: title, startsAt: now.addingTimeInterval(inMinutes * 60), isAllDay: allDay)
    }

    @Test func nothingToShowWhenTheCalendarIsEmpty() {
        #expect(UpcomingCalendarEvent.band(for: [], now: now) == nil)
    }

    @Test func picksTheSoonestAndCountsTheRest() {
        let band = UpcomingCalendarEvent.band(
            for: [event("1on1", inMinutes: 90), event("面談", inMinutes: 15), event("定例", inMinutes: 200)],
            now: now
        )
        #expect(band?.title == "面談")
        #expect(band?.minutesUntil == 15)
        #expect(band?.othersAhead == 2)
    }

    /// A birthday has no start time worth counting down to, and would otherwise
    /// hold the band for the whole day it belongs to.
    @Test func allDayEntriesNeverReachTheBand() {
        #expect(UpcomingCalendarEvent.band(for: [event("誕生日", inMinutes: 30, allDay: true)], now: now) == nil)
    }

    @Test func eventsAlreadyStartedAreNotNext() {
        #expect(UpcomingCalendarEvent.band(for: [event("始まった会議", inMinutes: -5)], now: now) == nil)
    }

    @Test func nothingBeyondTheHorizon() {
        #expect(UpcomingCalendarEvent.band(for: [event("明日の朝会", inMinutes: 9 * 60)], now: now) == nil)
        #expect(UpcomingCalendarEvent.band(for: [event("夕方", inMinutes: 7 * 60)], now: now) != nil)
    }

    /// Rounding down would let the band say "0 分" for the last full minute
    /// before something starts, which reads as "it is not happening".
    @Test func partialMinutesRoundUp() {
        let band = UpcomingCalendarEvent.band(for: [event("直前", inMinutes: 1.5)], now: now)
        #expect(band?.minutesUntil == 2)
    }

    @Test func aSingleEventHasNothingBehindIt() {
        #expect(UpcomingCalendarEvent.band(for: [event("唯一", inMinutes: 10)], now: now)?.othersAhead == 0)
    }
}
