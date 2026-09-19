import Foundation
import Testing
@testable import OpenIslandCore

struct MitamaJobCompletionTests {
    @Test("First poll returns empty (no burst)")
    func firstPollNoNotifications() {
        let now = Date()
        let completions = [
            MitamaJobCompletion(objective: "Old job 1", completedAt: now.addingTimeInterval(-3600)),
            MitamaJobCompletion(objective: "Old job 2", completedAt: now.addingTimeInterval(-1800)),
        ]
        let new = MitamaJobCompletionDetector.detectNew(current: completions, since: nil)
        #expect(new.isEmpty)
    }

    @Test("No new jobs returns empty")
    func noNewJobs() {
        let now = Date()
        let lastPoll = now.addingTimeInterval(-300)
        let completions = [
            MitamaJobCompletion(objective: "Old job", completedAt: now.addingTimeInterval(-600)),
        ]
        let new = MitamaJobCompletionDetector.detectNew(current: completions, since: lastPoll)
        #expect(new.isEmpty)
    }

    @Test("Detects single new job")
    func singleNewJob() {
        let now = Date()
        let lastPoll = now.addingTimeInterval(-300)
        let completions = [
            MitamaJobCompletion(objective: "New job", completedAt: now.addingTimeInterval(-60)),
            MitamaJobCompletion(objective: "Old job", completedAt: now.addingTimeInterval(-600)),
        ]
        let new = MitamaJobCompletionDetector.detectNew(current: completions, since: lastPoll)
        #expect(new.count == 1)
        #expect(new.first?.objective == "New job")
    }

    @Test("Detects multiple new jobs in order")
    func multipleNewJobsInOrder() {
        let now = Date()
        let lastPoll = now.addingTimeInterval(-400)
        let completions = [
            MitamaJobCompletion(objective: "Newest", completedAt: now.addingTimeInterval(-60)),
            MitamaJobCompletion(objective: "Middle", completedAt: now.addingTimeInterval(-180)),
            MitamaJobCompletion(objective: "Old", completedAt: now.addingTimeInterval(-600)),
        ]
        let new = MitamaJobCompletionDetector.detectNew(current: completions, since: lastPoll)
        #expect(new.count == 2)
        // Should be returned oldest first
        #expect(new[0].objective == "Middle")
        #expect(new[1].objective == "Newest")
    }

    @Test("Boundary: job exactly at lastPollTime is excluded")
    func boundaryJobAtLastPollExcluded() {
        let now = Date()
        let lastPoll = now.addingTimeInterval(-300)
        let completions = [
            MitamaJobCompletion(objective: "At boundary", completedAt: lastPoll),
            MitamaJobCompletion(objective: "Before", completedAt: now.addingTimeInterval(-600)),
        ]
        let new = MitamaJobCompletionDetector.detectNew(current: completions, since: lastPoll)
        #expect(new.isEmpty)
    }

    @Test("Boundary: job just after lastPollTime is included")
    func boundaryJobAfterLastPollIncluded() {
        let now = Date()
        let lastPoll = now.addingTimeInterval(-300)
        let justAfter = lastPoll.addingTimeInterval(0.1)
        let completions = [
            MitamaJobCompletion(objective: "Just after", completedAt: justAfter),
            MitamaJobCompletion(objective: "Before", completedAt: now.addingTimeInterval(-600)),
        ]
        let new = MitamaJobCompletionDetector.detectNew(current: completions, since: lastPoll)
        #expect(new.count == 1)
        #expect(new.first?.objective == "Just after")
    }

    @Test("Empty current list returns empty")
    func emptyCurrentList() {
        let now = Date()
        let lastPoll = now.addingTimeInterval(-300)
        let new = MitamaJobCompletionDetector.detectNew(current: [], since: lastPoll)
        #expect(new.isEmpty)
    }
}
