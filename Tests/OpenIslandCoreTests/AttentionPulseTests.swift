import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Attention pulse and status icon")
struct AttentionPulseTests {
    @Test("Repeat count fits whole cycles in the cap, never zero")
    func repeatCount() {
        #expect(AttentionPulse.repeatCount(period: 1.8) == 6)
        #expect(AttentionPulse.repeatCount(period: 0.9) == 13)
        #expect(AttentionPulse.repeatCount(period: 30) == 1)
        #expect(AttentionPulse.repeatCount(period: 0) == 1)
    }

    @Test("Waiting outranks running, running outranks idle")
    func iconStatePriority() {
        #expect(StatusIconState(attentionCount: 1, runningCount: 3) == .attention)
        #expect(StatusIconState(attentionCount: 0, runningCount: 2) == .running)
        #expect(StatusIconState(attentionCount: 0, runningCount: 0) == .idle)
    }
}
