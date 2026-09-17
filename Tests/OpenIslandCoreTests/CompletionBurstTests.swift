import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Completion burst")
struct CompletionBurstTests {
    @Test("Nothing is drawn before the burst or after it ends")
    func boundedInTime() {
        #expect(CompletionBurst.shards(at: 0).isEmpty)
        #expect(CompletionBurst.shards(at: CompletionBurst.duration).isEmpty)
        #expect(CompletionBurst.rings(at: CompletionBurst.duration).isEmpty)
        #expect(CompletionBurst.flare(at: -1).opacity == 0)
        #expect(CompletionBurst.flare(at: CompletionBurst.duration).opacity == 0)
    }

    @Test("Shards fly down and out, stay on screen, and fade")
    func shardsFlyDownAndFade() {
        let early = CompletionBurst.shards(at: 0.1)
        let late = CompletionBurst.shards(at: 1.0)
        #expect(early.count == CompletionBurst.shardCount)
        #expect(early == CompletionBurst.shards(at: 0.1))
        for (a, b) in zip(early, late) {
            #expect(b.y > 0)
            #expect(abs(b.x) <= 1.0)
            #expect(b.y <= 1.2)
            #expect(hypot(b.x, b.y) >= hypot(a.x, a.y))
            #expect(b.opacity < a.opacity)
        }
        // Spread both ways from the notch, not all to one side.
        #expect(late.contains { $0.x < -0.2 })
        #expect(late.contains { $0.x > 0.2 })
    }

    @Test("The rings expand and the second trails the first")
    func ringsTrail() {
        let rings = CompletionBurst.rings(at: 0.3)
        #expect(rings.count == 2)
        #expect(rings[0].radius > rings[1].radius)
        #expect(CompletionBurst.rings(at: 0.05).count == 1)
    }

    @Test("The flare opens to full width and is gone well before the end")
    func flareOpensThenFades() {
        #expect(CompletionBurst.flare(at: 0.3).width == 1)
        #expect(CompletionBurst.flare(at: 0.08).opacity > 0.99)
        #expect(CompletionBurst.flare(at: 0.6).opacity == 0)
    }
}
