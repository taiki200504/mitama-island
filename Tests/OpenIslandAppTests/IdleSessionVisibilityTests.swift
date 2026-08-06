import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

@Suite("Grey rows stay out of the list", .serialized)
@MainActor
struct IdleSessionVisibilityTests {
    private func makeModel() -> AppModel {
        let defaults = UserDefaults(suiteName: "idle-\(UUID().uuidString)")!
        return AppModel(settings: SettingsStore(store: PreferenceStore(suite: defaults)))
    }

    private func session(id: String, phase: SessionPhase, minutesAgo: Double) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: id,
            tool: .claudeCode,
            phase: phase,
            summary: "",
            updatedAt: Date.now.addingTimeInterval(-minutesAgo * 60)
        )
        // Without this a finished session never reaches the list at all, so the
        // filter under test would not be exercised.
        session.isProcessAlive = true
        return session
    }

    private func load(_ model: AppModel, _ sessions: [AgentSession]) {
        model.state = SessionState(sessions: sessions)
    }

    private func listedIDs(_ model: AppModel) -> Set<String> {
        Set(model.islandSessionSections.flatMap(\.sessions).map(\.id))
    }

    /// The row that prompted this: finished a while ago, rendered grey, sitting
    /// next to work that is actually happening. Ten minutes is past the default
    /// five-minute greying point but still recent enough to reach the list, which
    /// is exactly the case the old code showed and this one hides.
    @Test("A row that has gone grey is dropped")
    func dropsGreyRows() {
        let model = makeModel()
        load(model, [
            session(id: "live", phase: .running, minutesAgo: 0),
            session(id: "grey", phase: .completed, minutesAgo: 10),
        ])
        #expect(listedIDs(model) == ["live"])
    }

    /// A session that finished a moment ago is not grey yet, and hiding it would
    /// take away the summary the user is most likely to want.
    @Test("A just-finished row is kept")
    func keepsFreshCompletions() {
        let model = makeModel()
        load(model, [
            session(id: "live", phase: .running, minutesAgo: 0),
            session(id: "fresh", phase: .completed, minutesAgo: 1),
        ])
        #expect(listedIDs(model).contains("fresh"))
    }

    /// A session waiting on the user is never quiet, however long it has waited.
    @Test("A row waiting on the user is always kept")
    func keepsBlockedRows() {
        let model = makeModel()
        load(model, [
            session(id: "approval", phase: .waitingForApproval, minutesAgo: 600),
            session(id: "question", phase: .waitingForAnswer, minutesAgo: 600),
        ])
        #expect(listedIDs(model) == ["approval", "question"])
    }

    /// An empty list reads as the app having lost track, which is worse than
    /// showing one stale row.
    /// A populated list must not become an empty one. Rows too old to reach this
    /// filter were already excluded further up, which is a separate thing.
    @Test("Grey rows are kept when they are all there is")
    func neverEmptiesTheList() {
        let model = makeModel()
        load(model, [
            session(id: "grey-a", phase: .completed, minutesAgo: 10),
            session(id: "grey-b", phase: .completed, minutesAgo: 12),
        ])
        #expect(!listedIDs(model).isEmpty)
    }

    @Test("Turning it off shows everything again")
    func settingIsRespected() {
        let model = makeModel()
        model.settings.display.hideIdleSessions = false
        load(model, [
            session(id: "live", phase: .running, minutesAgo: 0),
            session(id: "grey", phase: .completed, minutesAgo: 10),
        ])
        #expect(listedIDs(model) == ["live", "grey"])
    }

    /// The setting itself has to default to hiding — that is what was asked for.
    @Test("Hiding is on out of the box")
    func hidingIsDefault() {
        #expect(makeModel().settings.display.hideIdleSessions)
    }
}

@Suite("The badge agrees with the list", .serialized)
@MainActor
struct IslandCountConsistencyTests {
    private func makeModel() -> AppModel {
        let defaults = UserDefaults(suiteName: "count-\(UUID().uuidString)")!
        return AppModel(settings: SettingsStore(store: PreferenceStore(suite: defaults)))
    }

    private func session(id: String, phase: SessionPhase, minutesAgo: Double) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: id,
            tool: .claudeCode,
            phase: phase,
            summary: "",
            updatedAt: Date.now.addingTimeInterval(-minutesAgo * 60)
        )
        session.isProcessAlive = true
        return session
    }

    /// The closed island's count came from a different derivation than the list,
    /// so hiding the grey rows left the pill reading ×5 and opening onto two.
    @Test("The count matches the number of rows")
    func countMatchesRows() {
        let model = makeModel()
        model.state = SessionState(sessions: [
            session(id: "live", phase: .running, minutesAgo: 0),
            session(id: "fresh", phase: .completed, minutesAgo: 1),
            session(id: "grey-a", phase: .completed, minutesAgo: 10),
            session(id: "grey-b", phase: .completed, minutesAgo: 12),
        ])
        model.settings.display.hideIdleSessions = true
        #expect(model.liveSessionCount == model.islandListSessions.count)
    }

    @Test("They still match with hiding turned off")
    func countMatchesWithHidingOff() {
        let model = makeModel()
        model.state = SessionState(sessions: [
            session(id: "live", phase: .running, minutesAgo: 0),
            session(id: "grey", phase: .completed, minutesAgo: 10),
        ])
        model.settings.display.hideIdleSessions = false
        #expect(model.liveSessionCount == model.islandListSessions.count)
    }

    @Test("An empty island counts nothing")
    func emptyCountsZero() {
        let model = makeModel()
        model.state = SessionState(sessions: [])
        #expect(model.liveSessionCount == 0)
        #expect(model.islandListSessions.isEmpty)
    }
}
