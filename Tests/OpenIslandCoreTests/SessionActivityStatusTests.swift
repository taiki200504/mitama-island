import Foundation
import Testing
import OpenIslandCore

@Suite
struct SessionActivityStatusTests {
    let referenceDate = Date(timeIntervalSince1970: 1_000_000)

    @Test("Stalled: running phase + 300+ seconds of inactivity")
    func stalledWithInactivity() {
        let lastActivity = referenceDate.addingTimeInterval(-301)
        let isStalled = SessionActivityStatus.isStalled(
            phase: .running,
            lastActivityTime: lastActivity,
            now: referenceDate
        )
        #expect(isStalled)
    }

    @Test("Not stalled: running phase but < 300 seconds")
    func notStalledBelowThreshold() {
        let lastActivity = referenceDate.addingTimeInterval(-299)
        let isStalled = SessionActivityStatus.isStalled(
            phase: .running,
            lastActivityTime: lastActivity,
            now: referenceDate
        )
        #expect(!isStalled)
    }

    @Test("Not stalled: boundary at exactly 300 seconds")
    func notStalledAtThreshold() {
        let lastActivity = referenceDate.addingTimeInterval(-300)
        let isStalled = SessionActivityStatus.isStalled(
            phase: .running,
            lastActivityTime: lastActivity,
            now: referenceDate
        )
        #expect(isStalled) // >= 300 means stalled
    }

    @Test("Not stalled: completed phase ignores inactivity")
    func completedPhaseIgnoresInactivity() {
        let lastActivity = referenceDate.addingTimeInterval(-3600)
        let isStalled = SessionActivityStatus.isStalled(
            phase: .completed,
            lastActivityTime: lastActivity,
            now: referenceDate
        )
        #expect(!isStalled)
    }

    @Test("Not stalled: waiting for approval ignores inactivity")
    func waitingForApprovalIgnoresInactivity() {
        let lastActivity = referenceDate.addingTimeInterval(-3600)
        let isStalled = SessionActivityStatus.isStalled(
            phase: .waitingForApproval,
            lastActivityTime: lastActivity,
            now: referenceDate
        )
        #expect(!isStalled)
    }

    @Test("Not stalled: nil lastActivityTime")
    func nilActivityTimeNotStalled() {
        let isStalled = SessionActivityStatus.isStalled(
            phase: .running,
            lastActivityTime: nil,
            now: referenceDate
        )
        #expect(!isStalled)
    }

    @Test("Elapsed time formatting: seconds")
    func elapsedTimeSeconds() {
        let lastActivity = referenceDate.addingTimeInterval(-45)
        let text = SessionActivityStatus.elapsedTimeText(
            since: lastActivity,
            now: referenceDate
        )
        #expect(text == "45s")
    }

    @Test("Elapsed time formatting: minutes")
    func elapsedTimeMinutes() {
        let lastActivity = referenceDate.addingTimeInterval(-180)
        let text = SessionActivityStatus.elapsedTimeText(
            since: lastActivity,
            now: referenceDate
        )
        #expect(text == "3m")
    }

    @Test("Elapsed time formatting: hours")
    func elapsedTimeHours() {
        let lastActivity = referenceDate.addingTimeInterval(-7200)
        let text = SessionActivityStatus.elapsedTimeText(
            since: lastActivity,
            now: referenceDate
        )
        #expect(text == "2h")
    }
}
