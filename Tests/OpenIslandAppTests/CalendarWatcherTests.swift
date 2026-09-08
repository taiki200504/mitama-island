import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
@Suite struct CalendarWatcherTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - `current(at:)` reads live, not from a snapshot

    @Test("A fixture-loaded event disappears the moment `now` passes its endsAt")
    func fixtureCurrentExpiresAtEndsAt() {
        let watcher = CalendarWatcher()
        let startsAt = now
        let endsAt = now.addingTimeInterval(600)
        let current = UpcomingCalendarEvent.Current(title: "朝会", startsAt: startsAt, endsAt: endsAt, url: nil)
        watcher.loadFixture(band: nil, current: current)

        #expect(watcher.current(at: startsAt.addingTimeInterval(60))?.title == "朝会")
        // `endsAt` itself is already "not in progress" — see
        // `UpcomingCalendarEvent.current`'s `now < endsAt` check.
        #expect(watcher.current(at: endsAt) == nil)
        #expect(watcher.current(at: endsAt.addingTimeInterval(1)) == nil)
    }

    @Test("No fixture loaded means nothing current, at any time")
    func noFixtureMeansNoCurrent() {
        let watcher = CalendarWatcher()
        #expect(watcher.current(at: now) == nil)
    }

    // MARK: - `nextWake` scheduling

    @Test("An entry in progress that ends before anything else starts wakes for its own end")
    func nextWakePicksTheSoonerEnd() {
        let inProgress = UpcomingCalendarEvent.Event(
            title: "進行中", startsAt: now.addingTimeInterval(-300), endsAt: now.addingTimeInterval(120), isAllDay: false
        )
        let upcoming = UpcomingCalendarEvent.Event(
            title: "次", startsAt: now.addingTimeInterval(500), endsAt: now.addingTimeInterval(600), isAllDay: false
        )
        #expect(CalendarWatcher.nextWake(for: [inProgress, upcoming], now: now) == inProgress.endsAt)
    }

    @Test("Something starting sooner than the current entry ends wakes for the start")
    func nextWakePicksTheSoonerStart() {
        let inProgress = UpcomingCalendarEvent.Event(
            title: "進行中", startsAt: now.addingTimeInterval(-300), endsAt: now.addingTimeInterval(1_800), isAllDay: false
        )
        let upcoming = UpcomingCalendarEvent.Event(
            title: "次", startsAt: now.addingTimeInterval(60), endsAt: now.addingTimeInterval(900), isAllDay: false
        )
        #expect(CalendarWatcher.nextWake(for: [inProgress, upcoming], now: now) == upcoming.startsAt)
    }

    @Test("Moving an event later moves what it's armed to wake for")
    func movingAnEventLaterMovesNextWake() {
        let original = UpcomingCalendarEvent.Event(
            title: "会議", startsAt: now.addingTimeInterval(300), endsAt: now.addingTimeInterval(1_800), isAllDay: false
        )
        #expect(CalendarWatcher.nextWake(for: [original], now: now) == original.startsAt)

        let moved = UpcomingCalendarEvent.Event(
            title: "会議", startsAt: now.addingTimeInterval(900), endsAt: now.addingTimeInterval(2_400), isAllDay: false
        )
        #expect(CalendarWatcher.nextWake(for: [moved], now: now) == moved.startsAt)
    }

    @Test("Nothing upcoming and nothing in progress means nothing worth waking for")
    func nothingToWakeForWhenCalendarIsQuiet() {
        #expect(CalendarWatcher.nextWake(for: [], now: now) == nil)
    }

    @Test("An all-day entry contributes neither a start nor an end to wake for")
    func allDayEntriesNeverArmAnAlarm() {
        let allDay = UpcomingCalendarEvent.Event(
            title: "終日", startsAt: now.addingTimeInterval(-60), endsAt: now.addingTimeInterval(3_600), isAllDay: true
        )
        #expect(CalendarWatcher.nextWake(for: [allDay], now: now) == nil)
    }

    @Test("Two entries starting at the exact same instant wake for the earlier-ending one, tie broken by title")
    func sameStartOverlapWakesForTheTitleOrderWinner() {
        let zebra = UpcomingCalendarEvent.Event(
            title: "Zebra", startsAt: now.addingTimeInterval(-10), endsAt: now.addingTimeInterval(300), isAllDay: false
        )
        let apple = UpcomingCalendarEvent.Event(
            title: "Apple", startsAt: now.addingTimeInterval(-10), endsAt: now.addingTimeInterval(600), isAllDay: false
        )
        // `UpcomingCalendarEvent.current` picks "Apple" (earlier title, same
        // start), so the wake this arms for is Apple's end, not Zebra's.
        #expect(CalendarWatcher.nextWake(for: [zebra, apple], now: now) == apple.endsAt)
    }
}
