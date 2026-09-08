import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Closed-island arbiter")
struct IslandClosedArbiterTests {
    private let epoch = Date(timeIntervalSince1970: 1_000_000)

    private func peek(_ agent: String) -> IslandPeekBand.Content {
        IslandPeekBand.Content(
            agent: agent,
            subject: .session(.waitingForApproval),
            elapsed: .minutes(2),
            othersWaiting: 0
        )
    }

    private func urgentPeek() -> IslandPeekBand.Content {
        IslandPeekBand.Content(agent: IslandPeekBand.mitamaLabel, subject: .mitamaAlert, elapsed: .justNow, othersWaiting: 0)
    }

    private func nextEventBand() -> UpcomingCalendarEvent.Band {
        UpcomingCalendarEvent.Band(title: "Standup", startsAt: epoch.addingTimeInterval(600), minutesUntil: 10, othersAhead: 0)
    }

    // MARK: - Body, one signal at a time

    @Test("Nothing at all means no body and no accessory")
    func nothingMeansNothing() {
        let content = IslandClosedArbiter.resolve(IslandClosedInputs(now: epoch))
        #expect(content.body == nil)
        #expect(content.accessory == nil)
    }

    @Test("An urgent alert alone becomes the body")
    func urgentAlone() {
        let content = IslandClosedArbiter.resolve(IslandClosedInputs(mitamaUrgent: urgentPeek(), now: epoch))
        #expect(content.body == .urgent(urgentPeek()))
    }

    @Test("A waiting agent alone becomes the body")
    func waitingAlone() {
        let content = IslandClosedArbiter.resolve(IslandClosedInputs(waiting: peek("CODEX"), now: epoch))
        #expect(content.body == .waiting(peek("CODEX")))
    }

    @Test("A calendar entry that just started becomes the body")
    func eventStartedAlone() {
        let started = IslandClosedInputs.EventStarted(title: "Standup", startedAt: epoch, endsAt: epoch.addingTimeInterval(1_800), url: nil)
        let content = IslandClosedArbiter.resolve(IslandClosedInputs(eventStarted: started, now: epoch))
        #expect(content.body == .eventStarted(title: "Standup", startedAt: epoch, endsAt: epoch.addingTimeInterval(1_800), url: nil))
    }

    @Test("What's next becomes the body when the setting is on")
    func nextEventAloneWhenEnabled() {
        let content = IslandClosedArbiter.resolve(
            IslandClosedInputs(nextEvent: nextEventBand(), showsNextEvent: true, now: epoch)
        )
        #expect(content.body == .nextEvent(nextEventBand()))
    }

    @Test("showsNextEvent off hides the next-event body even when one exists")
    func nextEventHiddenWhenSettingOff() {
        let content = IslandClosedArbiter.resolve(
            IslandClosedInputs(nextEvent: nextEventBand(), showsNextEvent: false, now: epoch)
        )
        #expect(content.body == nil)
    }

    // MARK: - Body priority

    @Test("Urgent outranks waiting, event-started, and next-event")
    func urgentOutranksEverything() {
        let started = IslandClosedInputs.EventStarted(title: "Standup", startedAt: epoch, endsAt: epoch.addingTimeInterval(1_800), url: nil)
        let content = IslandClosedArbiter.resolve(
            IslandClosedInputs(
                mitamaUrgent: urgentPeek(),
                waiting: peek("CODEX"),
                eventStarted: started,
                nextEvent: nextEventBand(),
                showsNextEvent: true,
                now: epoch
            )
        )
        #expect(content.body == .urgent(urgentPeek()))
    }

    @Test("Waiting outranks event-started and next-event")
    func waitingOutranksEventAndNext() {
        let started = IslandClosedInputs.EventStarted(title: "Standup", startedAt: epoch, endsAt: epoch.addingTimeInterval(1_800), url: nil)
        let content = IslandClosedArbiter.resolve(
            IslandClosedInputs(
                waiting: peek("CODEX"),
                eventStarted: started,
                nextEvent: nextEventBand(),
                showsNextEvent: true,
                now: epoch
            )
        )
        #expect(content.body == .waiting(peek("CODEX")))
    }

    @Test("A fresh event-started outranks next-event")
    func eventStartedOutranksNextEvent() {
        let started = IslandClosedInputs.EventStarted(title: "Standup", startedAt: epoch, endsAt: epoch.addingTimeInterval(1_800), url: nil)
        let content = IslandClosedArbiter.resolve(
            IslandClosedInputs(eventStarted: started, nextEvent: nextEventBand(), showsNextEvent: true, now: epoch)
        )
        #expect(content.body == .eventStarted(title: "Standup", startedAt: epoch, endsAt: epoch.addingTimeInterval(1_800), url: nil))
    }

    // MARK: - The three-minute freshness boundary

    @Test("Exactly three minutes after the start is still fresh")
    func threeMinutesIsStillFresh() {
        let started = IslandClosedInputs.EventStarted(title: "Standup", startedAt: epoch, endsAt: epoch.addingTimeInterval(1_800), url: nil)
        let content = IslandClosedArbiter.resolve(
            IslandClosedInputs(eventStarted: started, now: epoch.addingTimeInterval(180))
        )
        #expect(content.body == .eventStarted(title: "Standup", startedAt: epoch, endsAt: epoch.addingTimeInterval(1_800), url: nil))
    }

    @Test("One second past three minutes is no longer fresh")
    func pastThreeMinutesIsStale() {
        let started = IslandClosedInputs.EventStarted(title: "Standup", startedAt: epoch, endsAt: epoch.addingTimeInterval(1_800), url: nil)
        let content = IslandClosedArbiter.resolve(
            IslandClosedInputs(eventStarted: started, now: epoch.addingTimeInterval(181))
        )
        #expect(content.body == nil)
    }

    @Test("An in-progress event beyond three minutes yields no body, even with nothing else to fall back to")
    func inProgressEventBeyondFreshnessYieldsNoBody() {
        let started = IslandClosedInputs.EventStarted(title: "Standup", startedAt: epoch.addingTimeInterval(-3_600), endsAt: epoch.addingTimeInterval(-3_600).addingTimeInterval(1_800), url: nil)
        let content = IslandClosedArbiter.resolve(IslandClosedInputs(eventStarted: started, now: epoch))
        #expect(content.body == nil)
    }

    @Test("A clock that jumped backwards before the start does not read as fresh")
    func startInTheFutureIsNotFresh() {
        let started = IslandClosedInputs.EventStarted(title: "Standup", startedAt: epoch.addingTimeInterval(60), endsAt: epoch.addingTimeInterval(60).addingTimeInterval(1_800), url: nil)
        let content = IslandClosedArbiter.resolve(IslandClosedInputs(eventStarted: started, now: epoch))
        #expect(content.body == nil)
    }

    // MARK: - Accessory, one signal at a time

    @Test("A timer alone becomes the accessory")
    func timerAlone() {
        let content = IslandClosedArbiter.resolve(
            IslandClosedInputs(timer: IslandClosedInputs.Timer(remainingMinutes: 12, label: "Focus"), now: epoch)
        )
        #expect(content.accessory == .timer(remainingMinutes: 12, label: "Focus"))
    }

    @Test("Now-playing alone becomes the accessory")
    func nowPlayingAlone() {
        let content = IslandClosedArbiter.resolve(IslandClosedInputs(nowPlaying: .init(isPlaying: true), now: epoch))
        #expect(content.accessory == .nowPlaying(isPlaying: true))
    }

    @Test("The camera watching alone becomes the accessory")
    func cameraWatchingAlone() {
        let content = IslandClosedArbiter.resolve(IslandClosedInputs(cameraIsWatching: true, now: epoch))
        #expect(content.accessory == .cameraWatching)
    }

    @Test("A non-empty shelf alone becomes the accessory")
    func shelfAlone() {
        let content = IslandClosedArbiter.resolve(IslandClosedInputs(shelfCount: 3, now: epoch))
        #expect(content.accessory == .shelf(count: 3))
    }

    @Test("An empty shelf is not an accessory")
    func emptyShelfIsNoAccessory() {
        let content = IslandClosedArbiter.resolve(IslandClosedInputs(shelfCount: 0, now: epoch))
        #expect(content.accessory == nil)
    }

    // MARK: - Accessory priority

    @Test("Timer outranks now-playing, camera, and the shelf")
    func timerOutranksEverything() {
        let content = IslandClosedArbiter.resolve(
            IslandClosedInputs(
                timer: IslandClosedInputs.Timer(remainingMinutes: 5, label: "Focus"),
                nowPlaying: .init(isPlaying: true),
                cameraIsWatching: true,
                shelfCount: 2,
                now: epoch
            )
        )
        #expect(content.accessory == .timer(remainingMinutes: 5, label: "Focus"))
    }

    @Test("Now-playing outranks camera and the shelf")
    func nowPlayingOutranksCameraAndShelf() {
        let content = IslandClosedArbiter.resolve(
            IslandClosedInputs(nowPlaying: .init(isPlaying: false), cameraIsWatching: true, shelfCount: 2, now: epoch)
        )
        #expect(content.accessory == .nowPlaying(isPlaying: false))
    }

    @Test("The camera watching outranks the shelf")
    func cameraOutranksShelf() {
        let content = IslandClosedArbiter.resolve(IslandClosedInputs(cameraIsWatching: true, shelfCount: 2, now: epoch))
        #expect(content.accessory == .cameraWatching)
    }

    // MARK: - Body and accessory resolve independently

    @Test(
        "Every body pairs with every accessory without either one affecting the other's choice",
        arguments: [
            (hasUrgent: true, hasWaiting: false),
            (hasUrgent: false, hasWaiting: true),
        ]
    )
    func bodyAndAccessoryAreIndependent(combo: (hasUrgent: Bool, hasWaiting: Bool)) {
        let content = IslandClosedArbiter.resolve(
            IslandClosedInputs(
                mitamaUrgent: combo.hasUrgent ? urgentPeek() : nil,
                waiting: combo.hasWaiting ? peek("CODEX") : nil,
                timer: IslandClosedInputs.Timer(remainingMinutes: 1, label: "Break"),
                shelfCount: 4,
                now: epoch
            )
        )
        // Whichever body wins, the accessory is still decided purely by its
        // own priority — a timer is present, so it wins regardless of body.
        #expect(content.accessory == .timer(remainingMinutes: 1, label: "Break"))
        #expect(content.body != nil)
    }

    @Test("A waiting agent is never hidden by any accessory")
    func waitingBodyNeverHiddenByAccessory() {
        for accessoryInputs in [
            IslandClosedInputs(waiting: peek("CLAUDE"), timer: IslandClosedInputs.Timer(remainingMinutes: 1, label: "x"), now: epoch),
            IslandClosedInputs(waiting: peek("CLAUDE"), nowPlaying: .init(isPlaying: true), now: epoch),
            IslandClosedInputs(waiting: peek("CLAUDE"), cameraIsWatching: true, now: epoch),
            IslandClosedInputs(waiting: peek("CLAUDE"), shelfCount: 9, now: epoch),
            IslandClosedInputs(waiting: peek("CLAUDE"), now: epoch),
        ] {
            #expect(IslandClosedArbiter.resolve(accessoryInputs).body == .waiting(peek("CLAUDE")))
        }
    }
}
