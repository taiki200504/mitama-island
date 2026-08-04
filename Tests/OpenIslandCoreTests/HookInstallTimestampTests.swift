import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Hook install timestamp")
struct HookInstallTimestampTests {
    private func makeStore() -> AgentIntentStore {
        AgentIntentStore(defaults: UserDefaults(suiteName: "intent-\(UUID().uuidString)")!)
    }

    @Test("A fresh install has no timestamp")
    func startsEmpty() {
        #expect(makeStore().lastHookInstallDate == nil)
    }

    @Test("Installing records when it happened")
    func recordsInstall() {
        let store = makeStore()
        store.setIntent(.installed, for: .claudeCode)
        let recorded = try? #require(store.lastHookInstallDate)
        #expect(abs((recorded ?? .distantPast).timeIntervalSinceNow) < 5)
    }

    /// Uninstalling must not move the mark forward — the banner would then claim
    /// every running session predates an install that never happened.
    @Test("Other intents leave the timestamp alone")
    func otherIntentsDoNotRecord() {
        let store = makeStore()
        store.setIntent(.uninstalled, for: .claudeCode)
        store.setIntent(.untouched, for: .codex)
        #expect(store.lastHookInstallDate == nil)
    }
}
