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

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var refreshTimer: Task<Void, Never>?
    @ObservationIgnored private var changeObserver: NSObjectProtocol?

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
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
            self.changeObserver = nil
        }
        band = nil
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
                isAllDay: $0.isAllDay
            )
        }

        band = UpcomingCalendarEvent.band(for: events, now: now)
    }
}
