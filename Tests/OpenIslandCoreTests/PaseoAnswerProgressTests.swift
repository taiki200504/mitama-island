import Foundation
import Testing
@testable import OpenIslandCore

struct PaseoAnswerProgressTests {
    private func submission(
        at: Date = .now,
        target: String = "child-native",
        display: String = "parent-native"
    ) -> PaseoAnswerFollowthrough {
        PaseoAnswerFollowthrough(
            displaySessionID: display,
            targetSessionID: target,
            answeredRequestID: "req-1",
            channel: .paseoSDK,
            submittedAt: at,
            baselineSessionUpdatedAt: at.addingTimeInterval(-10)
        )
    }

    @Test func activityOnTargetSessionIsProgress() {
        let at = Date()
        let sub = submission(at: at)
        let event: AgentEvent = .activityUpdated(SessionActivityUpdated(
            sessionID: "child-native", summary: "Working", phase: .running, timestamp: at.addingTimeInterval(1)))
        #expect(PaseoAnswerProgress.evidence(from: event, submission: sub) == .sessionActivity)
    }

    @Test func activityOnDisplaySessionIsNotProgressWhenForwarded() {
        let at = Date()
        let sub = submission(at: at)
        let event: AgentEvent = .activityUpdated(SessionActivityUpdated(
            sessionID: "parent-native", summary: "Working", phase: .running, timestamp: at.addingTimeInterval(1)))
        #expect(PaseoAnswerProgress.evidence(from: event, submission: sub) == nil)
    }

    @Test func staleActivityIsNotProgress() {
        let at = Date()
        let sub = submission(at: at)
        let event: AgentEvent = .activityUpdated(SessionActivityUpdated(
            sessionID: "child-native", summary: "Working", phase: .running, timestamp: at.addingTimeInterval(-1)))
        #expect(PaseoAnswerProgress.evidence(from: event, submission: sub) == nil)
    }

    @Test func subsequentRequestOnTargetIsProgress() {
        let at = Date()
        let sub = submission(at: at)
        let event: AgentEvent = .permissionRequested(PermissionRequested(
            sessionID: "child-native",
            request: PermissionRequest(
                title: "next",
                summary: "echo",
                affectedPath: "/p",
                paseoContext: PaseoPermissionContext(
                    agentID: "agent", requestID: "req-2", provider: "claude", kind: "tool",
                    currentModeID: nil, currentModeLabel: nil, actions: []
                )
            ),
            timestamp: at.addingTimeInterval(1)))
        #expect(PaseoAnswerProgress.evidence(from: event, submission: sub) == .subsequentRequest)
    }
}