import Foundation
import Testing
@testable import OpenIslandCore

struct JarvisSummonTests {
    private let id = "1B4E28BA-2FA1-41D2-883F-0016D3CCA427"

    @Test("Every fixed state parses, with or without a request ID", arguments: JarvisSummon.State.allCases)
    func parsesFixedStates(state: JarvisSummon.State) {
        #expect(JarvisSummon.parse(userInfo: ["request": "", "state": state.rawValue])
                == JarvisSummon(requestID: nil, state: state))
        #expect(JarvisSummon.parse(userInfo: ["request": id.lowercased(), "state": state.rawValue])
                == JarvisSummon(requestID: UUID(uuidString: id), state: state))
    }

    @Test("Anything outside the fixed shape is dropped")
    func rejectsMalformed() {
        let bad: [[AnyHashable: Any]?] = [
            nil,
            [:],
            ["state": "listening"],
            ["request": ""],
            ["request": "", "state": "speaking"],
            ["request": "", "state": "LISTENING"],
            ["request": "not-a-uuid", "state": "done"],
            ["request": id + "0", "state": "done"],
            ["request": String(repeating: "a", count: 4096), "state": "done"],
            ["request": 42, "state": "done"],
            ["request": "", "state": 1],
            // 本文や予定を載せた通知は、状態が正しくても丸ごと捨てる
            ["request": "", "state": "done", "text": "今日の予定は3件です"],
            [1: "", "state": "done"],
        ]
        for userInfo in bad {
            #expect(JarvisSummon.parse(userInfo: userInfo) == nil)
        }
    }

    @Test("Only listening and results open the island; only running stays")
    func stateBehaviour() {
        #expect(JarvisSummon.State.listening.opensIsland)
        #expect(JarvisSummon.State.done.opensIsland)
        #expect(JarvisSummon.State.failed.opensIsland)
        #expect(!JarvisSummon.State.acking.opensIsland)
        #expect(!JarvisSummon.State.running.opensIsland)
        #expect(JarvisSummon.State.allCases.filter(\.persists) == [.running])
    }

    @Test("The same summon twice in a row is accepted once within the window")
    func dedupes() {
        var deduper = JarvisSummonDeduper(window: 5)
        let t0 = Date(timeIntervalSince1970: 1000)
        let listening = JarvisSummon(requestID: nil, state: .listening)
        let acking = JarvisSummon(requestID: nil, state: .acking)
        // accept は mutating なので、#expect の外で評価してから確かめる
        let results = [
            deduper.accept(listening, at: t0),
            deduper.accept(listening, at: t0.addingTimeInterval(1)),
            deduper.accept(acking, at: t0.addingTimeInterval(2)),
            deduper.accept(listening, at: t0.addingTimeInterval(3)),
            deduper.accept(listening, at: t0.addingTimeInterval(9)),
        ]
        #expect(results == [true, false, true, true, true])
    }
}
