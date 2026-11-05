import Foundation
import Testing
@testable import OpenIslandCore

private final class ActiveReads: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    private var maximum = 0
    private var count = 0
    func enter() { lock.lock(); active += 1; maximum = max(maximum, active); lock.unlock() }
    func leave() { lock.lock(); active -= 1; count += 1; lock.unlock() }
    var result: (maximum: Int, count: Int) {
        lock.lock(); defer { lock.unlock() }; return (maximum, count)
    }
}

struct MitamaKeychainConcurrencyTests {
    @Test func backgroundRelayAndMainReporterCannotReadTheKeychainTogether() {
        let reads = ActiveReads()
        // Synthetic bodies only: no keys, login keychain, or authentication UI.
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            MitamaKeychain.serializedRead {
                reads.enter()
                Thread.sleep(forTimeInterval: 0.001)
                reads.leave()
            }
        }
        #expect(reads.result.maximum == 1)
        #expect(reads.result.count == 64)
    }

    @Test func theGateIsReleasedForMissingOrSuccessfulValues() {
        #expect(MitamaKeychain.serializedRead { Optional<String>.none } == nil)
        #expect(MitamaKeychain.serializedRead { "synthetic" } == "synthetic")
    }
}
