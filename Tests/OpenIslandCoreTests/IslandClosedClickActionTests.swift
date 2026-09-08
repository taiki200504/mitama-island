import Foundation
import Testing
@testable import OpenIslandCore

@Suite struct IslandClosedClickActionTests {
    private let epoch = Date(timeIntervalSince1970: 1_000_000)

    @Test("No body at all expands, same as always")
    func nilBodyExpands() {
        #expect(IslandClosedClickAction.decide(body: nil) == .expand)
    }

    @Test("A waiting agent expands — nowhere else for the tap to go")
    func waitingExpands() {
        let peek = IslandPeekBand.Content(agent: "CODEX", subject: .session(.waitingForApproval), elapsed: .minutes(2), othersWaiting: 0)
        #expect(IslandClosedClickAction.decide(body: .waiting(peek)) == .expand)
    }

    @Test("An event that started with no URL expands")
    func eventStartedWithoutURLExpands() {
        let body = IslandClosedBody.eventStarted(title: "Standup", startedAt: epoch, endsAt: epoch.addingTimeInterval(1_800), url: nil)
        #expect(IslandClosedClickAction.decide(body: body) == .expand)
    }

    @Test("An event that started with a URL opens it instead of expanding")
    func eventStartedWithURLOpens() {
        let url = URL(string: "https://zoom.us/j/123")!
        let body = IslandClosedBody.eventStarted(title: "Standup", startedAt: epoch, endsAt: epoch.addingTimeInterval(1_800), url: url)
        #expect(IslandClosedClickAction.decide(body: body) == .open(url))
    }

    @Test("What's next never opens a URL — only the started body does")
    func nextEventExpands() {
        let band = UpcomingCalendarEvent.Band(title: "Standup", startsAt: epoch, minutesUntil: 5, othersAhead: 0)
        #expect(IslandClosedClickAction.decide(body: .nextEvent(band)) == .expand)
    }
}
