import AppKit
import EventKit
import Foundation
import Observation
import OpenIslandCore
import os

/// Keeps the next calendar entry in hand, so the closed island can say what is
/// coming while nothing is waiting on you.
///
/// Reads only. Never writes, never asks for access on its own: the request goes
/// out when the setting is switched on, because a permission dialog that
/// appears for no visible reason is one nobody can answer confidently.
@MainActor
@Observable
final class CalendarWatcher {
    private static let logger = Logger(subsystem: "com.mitama.island", category: "calendar")

    /// Nil when access is off, refused, or nothing qualifies.
    private(set) var band: UpcomingCalendarEvent.Band?

    /// The entry happening right now, if any.
    private(set) var current: UpcomingCalendarEvent.Current?

    /// Fires the moment an entry's start alarm goes off — not on every
    /// refresh, only when `armStartAlarm` actually sleeps through to a
    /// `startsAt`. `AppModel` turns this into the sound and the sneak peek.
    var onEventStarted: ((UpcomingCalendarEvent.Current) -> Void)?

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var refreshTimer: Task<Void, Never>?
    @ObservationIgnored private var changeObserver: NSObjectProtocol?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var startAlarmTask: Task<Void, Never>?
    /// What the last refresh saw, kept so `armStartAlarm` doesn't have to
    /// re-read the store just to find the next `startsAt`.
    @ObservationIgnored private var cachedEvents: [UpcomingCalendarEvent.Event] = []

    /// How often the calendar is re-read.
    ///
    /// The countdown itself is drawn from `startsAt` against the clock the pill
    /// already ticks once a minute, so this is only about entries being added,
    /// moved, or deleted. `EKEventStoreChanged` catches most of that; five
    /// minutes catches what a sync misses without waking the machine to ask.
    private static let refreshInterval: Duration = .seconds(300)

    var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Starts watching if access is already granted. Never prompts.
    func start() {
        guard hasAccess else {
            band = nil
            return
        }
        guard refreshTimer == nil else { return }

        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        // Sleep does not pause a running `Task`, but the clock it's sleeping
        // against stops advancing along with everything else — a machine that
        // slept through a 9am standup would otherwise fire the start alarm the
        // instant it wakes, for a meeting that started an hour ago. Waking is
        // exactly when a fresh read is worth its own refresh anyway.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        refreshTimer = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
    }

    func stop() {
        refreshTimer?.cancel()
        refreshTimer = nil
        startAlarmTask?.cancel()
        startAlarmTask = nil
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
            self.changeObserver = nil
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        band = nil
        current = nil
        cachedEvents = []
    }

    /// Lets the harness put the watcher in a known state without going
    /// through EventKit — the closed-island fixture and the ambient/opened
    /// surfaces all read `band`/`current` the same way whether they came from
    /// here or from a real refresh.
    func loadFixture(band: UpcomingCalendarEvent.Band?, current: UpcomingCalendarEvent.Current?) {
        self.band = band
        self.current = current
    }

    /// Asks for access, then starts. Called from the setting being switched on.
    func requestAccessAndStart() async {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            start()
        case .notDetermined:
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            Self.logger.notice("Access request returned granted=\(granted)")
            if granted { start() }
        default:
            // Denied, restricted, or write-only. Nothing to do from here — the
            // way back in is System Settings, which the setting's help says.
            Self.logger.notice("Access unavailable; not watching")
            band = nil
        }
    }

    private func refresh() {
        guard hasAccess else {
            band = nil
            current = nil
            cachedEvents = []
            return
        }

        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now,
            end: now.addingTimeInterval(UpcomingCalendarEvent.horizon),
            calendars: nil
        )

        let events = store.events(matching: predicate).map {
            UpcomingCalendarEvent.Event(
                // A calendar entry is allowed to have no title. Falling back to
                // an empty string here would put a blank row on the band.
                title: $0.title ?? "",
                startsAt: $0.startDate,
                endsAt: $0.endDate,
                url: MeetingLink.find(in: [$0.url?.absoluteString, $0.location, $0.notes]),
                isAllDay: $0.isAllDay
            )
        }

        cachedEvents = events
        band = UpcomingCalendarEvent.band(for: events, now: now)
        current = UpcomingCalendarEvent.current(for: events, now: now)
        armStartAlarm()
    }

    /// Sleeps until the next entry's `startsAt`, then fires `onEventStarted`
    /// and refreshes — which re-arms this for whatever comes after.
    ///
    /// Not on every tick of `refreshInterval`: an entry added, moved three
    /// minutes out, or the store simply cycling every five minutes would
    /// otherwise re-schedule a sleep whose remaining time already accounts
    /// for it, which this replaces wholesale each call rather than trying to
    /// reconcile with whatever the previous sleep was still waiting on.
    private func armStartAlarm() {
        startAlarmTask?.cancel()
        startAlarmTask = nil

        let now = Date()
        guard let nextStart = cachedEvents
            .filter({ !$0.isAllDay && $0.startsAt > now })
            .map(\.startsAt)
            .min()
        else { return }

        let delay = nextStart.timeIntervalSince(now)
        startAlarmTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.refresh()
            // `refresh()` just re-armed for whatever's next; only fire the
            // callback if the entry this woke up for is actually the one
            // that's now current — a moved or deleted entry should stay
            // silent rather than announcing a start that didn't happen.
            if let current = self.current, current.startsAt == nextStart {
                self.onEventStarted?(current)
            }
        }
    }
}
