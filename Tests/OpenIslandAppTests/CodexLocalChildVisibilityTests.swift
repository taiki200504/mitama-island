import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor struct CodexLocalChildVisibilityTests {
    private let parentID = "11111111-1111-4111-8111-111111111111"
    private let childID = "22222222-2222-4222-8222-222222222222"
    private func session(id: String, parent: String? = nil, phase: SessionPhase = .running) -> AgentSession {
        var session = AgentSession(id: id, title: parent == nil ? "Parent" : "Child", tool: .codex,
            origin: .live, attachmentState: .attached, phase: phase, summary: "Work", updatedAt: .now,
            codexMetadata: CodexSessionMetadata(parentThreadID: parent))
        session.isHookManaged = true
        session.isProcessAlive = true
        return session
    }
    private func model() -> AppModel {
        isolatedAppModel(paseoQuestions: PaseoQuestionCoordinator(call: { _, _ in .object(["permissions": .array([])]) }))
    }

    @Test func runningCompletedAndPermissionChildrenLeaveOneCommonQueue() {
        let model = model()
        let parent = session(id: parentID)
        for phase: SessionPhase in [.running, .completed, .waitingForApproval] {
            let child = session(id: childID, parent: parentID, phase: phase)
            model.state = SessionState(sessions: [parent, child])
            model.selectedSessionID = childID
            model.islandSurface = .sessionList(actionableSessionID: childID)
            #expect(model.islandListSessions.map(\.id) == [parentID])
            #expect(model.liveAttentionCount == 0)
            #expect(model.liveRunningCount == 1)
            #expect(model.focusedSession?.id == parentID)
            #expect(model.activeIslandCardSession == nil)
        }
    }

    @Test func ownQuestionStaysVisibleWithExactParentAttribution() {
        let model = model()
        let parent = session(id: parentID)
        var child = session(id: childID, parent: parentID, phase: .waitingForAnswer)
        child.questionPrompt = QuestionPrompt(title: "Which?", options: [], questions: [QuestionPromptItem(question: "Which?", header: "Choice", options: [])])
        model.state = SessionState(sessions: [parent, child])
        model.selectedSessionID = childID
        #expect(Set(model.islandListSessions.map(\.id)) == [parentID, childID])
        #expect(model.liveAttentionCount == 1)
        #expect(model.focusedSession?.id == childID)
        #expect(model.localCodexQuestionSourceTitle(sessionID: childID) == "Child（親: Parent）")
    }

    @Test func orphanEndedAndDetachedParentsDoNotHideChildrenAndCacheRefreshes() {
        let model = model()
        let child = session(id: childID, parent: parentID)
        model.state = SessionState(sessions: [child])
        #expect(model.islandListSessions.map(\.id) == [childID])
        let liveParent = session(id: parentID)
        model.state = SessionState(sessions: [liveParent, child])
        #expect(model.islandListSessions.map(\.id) == [parentID])
        var ended = liveParent
        ended.isSessionEnded = true
        model.state = SessionState(sessions: [ended, child])
        #expect(model.islandListSessions.contains { $0.id == childID })
        var finishedWithoutProcess = liveParent
        finishedWithoutProcess.phase = .completed
        finishedWithoutProcess.isProcessAlive = false
        model.state = SessionState(sessions: [finishedWithoutProcess, child])
        #expect(model.islandListSessions.contains { $0.id == childID })
        var detached = liveParent
        detached.attachmentState = .stale
        model.state = SessionState(sessions: [detached, child])
        #expect(model.islandListSessions.contains { $0.id == childID })
    }
}
