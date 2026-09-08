import Foundation
import Testing
@testable import OpenIslandCore

@Suite struct UpcomingCalendarEventTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(
        _ title: String,
        inMinutes: Double,
        durationMinutes: Double = 30,
        url: URL? = nil,
        allDay: Bool = false
    ) -> UpcomingCalendarEvent.Event {
        let startsAt = now.addingTimeInterval(inMinutes * 60)
        return .init(
            title: title,
            startsAt: startsAt,
            endsAt: startsAt.addingTimeInterval(durationMinutes * 60),
            url: url,
            isAllDay: allDay
        )
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

    // MARK: - `current`

    @Test("Start equal to now is in progress")
    func startEqualToNowIsCurrent() {
        let current = UpcomingCalendarEvent.current(for: [event("開始", inMinutes: 0)], now: now)
        #expect(current?.title == "開始")
    }

    @Test("End equal to now is no longer in progress")
    func endEqualToNowIsNotCurrent() {
        let current = UpcomingCalendarEvent.current(
            for: [event("終了", inMinutes: -30, durationMinutes: 30)],
            now: now
        )
        #expect(current == nil)
    }

    @Test("An all-day entry is never in progress")
    func allDayIsNeverCurrent() {
        let current = UpcomingCalendarEvent.current(
            for: [event("終日", inMinutes: -30, allDay: true)],
            now: now
        )
        #expect(current == nil)
    }

    @Test("Two overlapping entries pick whichever started first")
    func overlapPicksEarliestStart() {
        let current = UpcomingCalendarEvent.current(
            for: [
                event("後から始まった", inMinutes: -5, durationMinutes: 60),
                event("先に始まった", inMinutes: -20, durationMinutes: 60),
            ],
            now: now
        )
        #expect(current?.title == "先に始まった")
    }

    @Test("Two entries starting at the exact same instant break the tie by title")
    func sameStartOverlapBreaksTieByTitle() {
        let current = UpcomingCalendarEvent.current(
            for: [
                event("Zebra", inMinutes: -10, durationMinutes: 60),
                event("Apple", inMinutes: -10, durationMinutes: 60),
            ],
            now: now
        )
        #expect(current?.title == "Apple")
    }

    @Test("Nothing in progress means nil, even with something upcoming")
    func nothingInProgressYetIsNil() {
        #expect(UpcomingCalendarEvent.current(for: [event("これから", inMinutes: 5)], now: now) == nil)
    }

    @Test("The meeting link found on the entry rides along on `current`")
    func currentCarriesTheMeetingLink() {
        let url = URL(string: "https://zoom.us/j/123")!
        let current = UpcomingCalendarEvent.current(for: [event("同期", inMinutes: 0, url: url)], now: now)
        #expect(current?.url == url)
    }
}
