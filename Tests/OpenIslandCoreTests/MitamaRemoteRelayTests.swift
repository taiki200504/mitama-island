import Foundation
import Testing
@testable import OpenIslandCore

/// Records every request and answers from a closure, so the relay's decisions can be checked offline.
private final class FakeHTTP: MitamaRemoteHTTP, @unchecked Sendable {
    struct Call { let method: String; let table: String; let query: String; let body: [String: Any] }

    private let lock = NSLock()
    private var _calls: [Call] = []
    var respond: @Sendable (Call) -> String = { _ in "[]" }

    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }

    func perform(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        let url = request.url!
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let call = Call(
            method: request.httpMethod ?? "GET",
            table: url.lastPathComponent,
            query: url.query ?? "",
            body: body
        )
        lock.withLock { _calls.append(call) }
        return (Data(respond(call).utf8), 200)
    }
}

struct MitamaRemoteRelayTests {
    private let env = MitamaEnvironment(url: URL(string: "https://example.supabase.co")!, apiKey: "k")

    private func makeRelay(_ http: FakeHTTP, now: @escaping @Sendable () -> Date = { Date() }) -> MitamaRemoteRelay {
        let relay = MitamaRemoteRelay(http: http, environmentLoader: { env }, now: now, autoPoll: false)
        relay.isEnabled = true
        return relay
    }

    private func register(
        _ relay: MitamaRemoteRelay,
        id: String = "r1",
        kind: MitamaRemoteRelay.Kind = .permission,
        options: [String] = []
    ) async {
        await relay.register(
            id: id, sessionID: "s1", kind: kind, agentTool: "Claude Code", title: "Run rm",
            summary: "rm -rf build", options: options, primaryAction: "Allow", secondaryAction: "Deny"
        )
    }

    // MARK: summary

    @Test
    func longSummaryKeepsTheHeadAndTheTail() {
        let text = String(repeating: "a", count: 400) + String(repeating: "b", count: 400) + "TAIL-END"
        let summary = MitamaRemoteRelay.makeSummary(text)
        #expect(summary.count == 501)
        #expect(summary.hasPrefix(String(repeating: "a", count: 350) + "…"))
        #expect(summary.hasSuffix("TAIL-END"))
    }

    @Test
    func shortSummaryIsUntouched() {
        #expect(MitamaRemoteRelay.makeSummary("ls -la") == "ls -la")
    }

    @Test
    func secretsAreMaskedBeforeTheyLeave() {
        let out = MitamaRemoteRelay.makeSummary("curl -H 'Authorization: Bearer abc123' https://x && export API_KEY=sk-live-1 && echo ok; PASSWORD: hunter2")
        #expect(!out.contains("abc123"))
        #expect(!out.contains("sk-live-1"))
        #expect(!out.contains("hunter2"))
        #expect(out.contains("***"))
    }

    // MARK: register

    @Test
    func registrationInsertsOnceAndNeverSendsTheWorkingDirectory() async {
        let http = FakeHTTP()
        let relay = makeRelay(http)
        await register(relay)

        let calls = http.calls
        #expect(calls.map(\.table) == ["mos_island_requests", "mos_notifications"])
        #expect(calls.allSatisfy { $0.method == "POST" })
        #expect(calls[0].body["id"] as? String == "r1")
        #expect(calls[0].body["working_directory"] == nil)
        #expect(calls[1].body["level"] as? String == "urgent")
        #expect(calls[1].body["source_ref"] as? String == "island:r1")
        #expect(relay.pendingCountForTests() == 1)
    }

    @Test
    func disabledRelaySendsNothing() async {
        let http = FakeHTTP()
        let relay = makeRelay(http)
        relay.isEnabled = false
        await register(relay)
        #expect(http.calls.isEmpty)
        #expect(relay.pendingCountForTests() == 0)
    }

    // MARK: poll

    @Test
    func noPendingMeansNoPoll() async {
        let http = FakeHTTP()
        await makeRelay(http).pollOnce()
        #expect(http.calls.isEmpty)
    }

    @Test
    func answeredPermissionIsAppliedOnlyWhenTheClaimReturnsOneRow() async {
        let http = FakeHTTP()
        http.respond = { call in
            switch (call.method, call.table) {
            case ("GET", "mos_island_requests"): return #"[{"id":"r1","answer":"allow"}]"#
            case ("PATCH", _): return #"[{"id":"r1"}]"#
            default: return "[]"
            }
        }
        let relay = makeRelay(http)
        let applied = Recorder()
        relay.onResolvePermission = { applied.record("\($0):\($2)") }
        await register(relay)
        await relay.pollOnce()

        #expect(applied.values == ["s1:true"])
        #expect(relay.pendingCountForTests() == 0)
        let patch = http.calls.first { $0.method == "PATCH" }
        #expect(patch?.query.contains("status=eq.answered") == true)
        #expect(patch?.body["status"] as? String == "applied")
    }

    @Test
    func zeroRowsFromTheClaimMeansSomeoneElseAppliedIt() async {
        let http = FakeHTTP()
        http.respond = { call in
            switch (call.method, call.table) {
            case ("GET", "mos_island_requests"): return #"[{"id":"r1","answer":"allow"}]"#
            default: return "[]"
            }
        }
        let relay = makeRelay(http)
        let applied = Recorder()
        relay.onResolvePermission = { applied.record("\($0):\($2)") }
        await register(relay)
        await relay.pollOnce()

        #expect(applied.values.isEmpty)
    }

    @Test
    func answerOutsideTheOptionsIsDropped() async {
        let http = FakeHTTP()
        http.respond = { call in
            switch (call.method, call.table) {
            case ("GET", "mos_island_requests"): return #"[{"id":"r1","answer":"Delete everything"}]"#
            case ("PATCH", _): return #"[{"id":"r1"}]"#
            default: return "[]"
            }
        }
        let relay = makeRelay(http)
        let answered = Recorder()
        relay.onAnswerQuestion = { answered.record("\($0):\($2)") }
        await register(relay, kind: .question, options: ["Yes", "No"])
        await relay.pollOnce()

        #expect(answered.values.isEmpty)
        #expect(relay.pendingCountForTests() == 0)
    }

    @Test
    func validQuestionAnswerIsApplied() async {
        let http = FakeHTTP()
        http.respond = { call in
            switch (call.method, call.table) {
            case ("GET", "mos_island_requests"): return #"[{"id":"r1","answer":"No"}]"#
            case ("PATCH", _): return #"[{"id":"r1"}]"#
            default: return "[]"
            }
        }
        let relay = makeRelay(http)
        let answered = Recorder()
        relay.onAnswerQuestion = { answered.record("\($0):\($2)") }
        await register(relay, kind: .question, options: ["Yes", "No"])
        await relay.pollOnce()

        #expect(answered.values == ["s1:No"])
    }

    @Test
    func requestsOlderThanThirtyMinutesAreExpired() async {
        let http = FakeHTTP()
        let clock = Clock(Date(timeIntervalSince1970: 1_000_000))
        let relay = makeRelay(http) { clock.date }
        await register(relay)
        clock.date = clock.date.addingTimeInterval(31 * 60)
        await relay.pollOnce()

        let patch = http.calls.first { $0.method == "PATCH" }
        #expect(patch?.body["status"] as? String == "expired")
        #expect(patch?.query.contains("status=eq.pending") == true)
        #expect(relay.pendingCountForTests() == 0)
    }

    // MARK: resolved on the Mac

    @Test
    func answeringOnTheMacMarksEverySessionRequestResolvedElsewhere() async {
        let http = FakeHTTP()
        let relay = makeRelay(http)
        await register(relay, id: "r1")
        await register(relay, id: "r2")
        await relay.resolveElsewhere(sessionID: "s1")

        let patch = http.calls.first { $0.method == "PATCH" }
        #expect(patch?.body["status"] as? String == "resolved_elsewhere")
        #expect(patch?.query.contains("r1") == true && patch?.query.contains("r2") == true)
        #expect(relay.pendingCountForTests() == 0)
    }
}

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [String] = []
    func record(_ value: String) { lock.lock(); _values.append(value); lock.unlock() }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return _values }
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var _date: Date
    init(_ date: Date) { _date = date }
    var date: Date {
        get { lock.lock(); defer { lock.unlock() }; return _date }
        set { lock.lock(); _date = newValue; lock.unlock() }
    }
}
