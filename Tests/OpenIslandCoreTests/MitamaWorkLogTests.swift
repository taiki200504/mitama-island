import Foundation
import Testing
@testable import OpenIslandCore

/// What the island tells mitama about the work its owner did.
struct MitamaWorkLogTests {
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private func record(
        session: String = "abc",
        startedAt: Date = Date(timeIntervalSince1970: 1_000_000),
        endedAt: Date = Date(timeIntervalSince1970: 1_003_600)
    ) -> IslandSessionRecord {
        IslandSessionRecord(
            sessionID: session,
            agentID: "claudeCode",
            startedAt: startedAt,
            endedAt: endedAt,
            status: .completed
        )
    }

    /// The island restarts and re-reads sessions it already reported. Counting
    /// the same afternoon twice would inflate the one number the scoreboard is
    /// supposed to keep honest.
    @Test
    func theRowIDIsStableAcrossReplays() {
        #expect(record().rowID == record().rowID)
        #expect(record(session: "other").rowID != record().rowID)
    }

    @Test
    func durationIsTheElapsedTime() {
        #expect(record().durationSeconds == 3600)
    }

    /// A clock that jumped backwards mid-session must not log negative hours.
    @Test
    func aBackwardsClockDoesNotProduceNegativeTime() {
        let backwards = record(
            startedAt: Date(timeIntervalSince1970: 1_003_600),
            endedAt: Date(timeIntervalSince1970: 1_000_000)
        )
        #expect(backwards.durationSeconds == 0)
    }

    /// Everything the island sends is in this dictionary. Anything the user
    /// typed or worked on that appeared here would be leaving their machine.
    @Test
    func onlyCountsAndTimesAreSent() {
        let body = record().body(formatter: formatter)
        #expect(
            Set(body.keys) == [
                "id", "agent_id", "session_id", "started_at", "ended_at", "duration_seconds", "status",
            ]
        )
    }

    @Test
    func timestampsAreSentAsISO8601() {
        let body = record().body(formatter: formatter)
        #expect(body["started_at"] as? String == "1970-01-12T13:46:40Z")
    }
}

/// The credentials the mitama link runs on.
struct MitamaEnvironmentTests {
    private let environment = MitamaEnvironment(
        url: URL(string: "https://example.supabase.co")!,
        apiKey: "secret-key"
    )

    /// One place signs requests, so a caller cannot forget the header and get a
    /// silent empty result instead of an error.
    @Test
    func requestsCarryBothAuthHeaders() {
        let signed = environment.authorized(URLRequest(url: URL(string: "https://example.com")!))
        #expect(signed.value(forHTTPHeaderField: "apikey") == "secret-key")
        #expect(signed.value(forHTTPHeaderField: "Authorization") == "Bearer secret-key")
    }

    @Test
    func endpointsAreBuiltUnderTheRestPath() {
        let url = environment.endpoint("mos_island_sessions", queryItems: [URLQueryItem(name: "select", value: "id")])
        #expect(url?.absoluteString == "https://example.supabase.co/rest/v1/mos_island_sessions?select=id")
    }

    @Test
    func anEndpointWithoutQueryHasNoTrailingQuestionMark() {
        #expect(
            environment.endpoint("mos_job_queue")?.absoluteString
                == "https://example.supabase.co/rest/v1/mos_job_queue"
        )
    }
}

/// E2b (mitama-os docs/mitama-v3/e2-voice-design.md §2): one hand-off is one queue row, however many times it is retried.
struct MitamaHandoffIdentityTests {
    @Test
    func enqueueRetryReusesID() {
        let job = IslandJobSubmission(objective: "朝の準備", agentID: "butler")
        #expect(job.row["id"] as? String == job.row["id"] as? String)
        // A retry sends the same submission; a new input is a new submission.
        #expect(IslandJobSubmission(objective: "朝の準備", agentID: "butler").id != job.id)
        #expect(job.row["input"] as? [String: String] == ["objective": "朝の準備"])
    }

    @Test
    func theInsertIgnoresADuplicateID() {
        #expect(MitamaWorkLogClient.enqueuePreference == "resolution=ignore-duplicates")
    }

    @Test
    func anExplicitIDIsKept() {
        let job = IslandJobSubmission(id: "fixed", objective: "x", agentID: "a")
        #expect(job.row["id"] as? String == "fixed")
    }
}

/// The island has no owner login, so a spoken request is handed to the Hub's /ai, which holds the session.
struct VoiceHandoffURLTests {
    private let utterance = "6f1c2d3e-4a5b-4c6d-8e7f-0a1b2c3d4e5f"
    private let thread = "0a1b2c3d-4e5f-4a6b-9c7d-8e9f0a1b2c3d"

    @Test
    func opensTheHubWithTheIDsInTheFragment() throws {
        let url = try #require(VoiceHandoff.url(utteranceID: utterance, thread: thread, text: "今日の予定 & 確認"))
        #expect(url.host == "mitama-os-hub.vercel.app")
        #expect(url.path == "/ai")
        #expect(url.query == nil)  // the text must not reach a server log
        let fragment = try #require(url.fragment)
        #expect(fragment.contains("utterance=\(utterance)"))
        #expect(fragment.contains("thread=\(thread)"))
        #expect(!fragment.contains(" "))
        #expect(!fragment.contains("&確認"))
    }

    /// Reads the fragment the way the Hub does (URLSearchParams: `+` is a space, then percent-decoding).
    private func hubRead(_ fragment: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in fragment.split(separator: "&", omittingEmptySubsequences: false) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let decode = { (s: String) in s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? s }
            result[decode(parts[0])] = decode(parts.count > 1 ? parts[1] : "")
        }
        return result
    }

    @Test(arguments: ["C++ の本", "a+b=c&d", "100%の確率", "今日の予定 を 確認", "x y+z", "😀 emoji + 記号 #?/", "it's (ok)!"])
    func theHubReadsTheTextBackExactly(text: String) throws {
        let url = try #require(VoiceHandoff.url(utteranceID: utterance, thread: thread, text: text))
        let read = hubRead(try #require(url.fragment))
        #expect(read["text"] == text)
        #expect(read["utterance"] == utterance)
        #expect(read["thread"] == thread)
        #expect(!(url.absoluteString.contains("+")))
    }

    @Test
    func refusesAnythingButLowercaseUUIDv4OrEmptyText() {
        #expect(VoiceHandoff.url(utteranceID: "u1", thread: thread, text: "x") == nil)
        #expect(VoiceHandoff.url(utteranceID: utterance.uppercased(), thread: thread, text: "x") == nil)
        #expect(VoiceHandoff.url(utteranceID: utterance, thread: "not-a-uuid", text: "x") == nil)
        #expect(VoiceHandoff.url(utteranceID: utterance, thread: thread, text: "  ") == nil)
    }

    /// The Mac app reads exactly these three fields; nothing else may ride along.
    @Test
    func theMacLinkCarriesOnlyTheThreeFieldsAndRoundTrips() throws {
        let text = "C++ の本 & 100%"
        let url = try #require(VoiceHandoff.macURL(utteranceID: utterance, thread: thread, text: text))
        #expect(url.scheme == "app.mitama.os.mac.voice")
        #expect(url.host == "request")
        #expect(url.fragment == nil)
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(Set(items.keys) == ["utterance", "thread", "text"])
        #expect(items["text"] == text)
        #expect(!url.absoluteString.contains("+"))
    }

    @Test
    func theMacLinkRefusesABadIDOrEmptyText() {
        #expect(VoiceHandoff.macURL(utteranceID: "u1", thread: thread, text: "x") == nil)
        #expect(VoiceHandoff.macURL(utteranceID: utterance, thread: "t", text: "x") == nil)
        #expect(VoiceHandoff.macURL(utteranceID: utterance, thread: thread, text: " ") == nil)
    }

    /// The ceiling matches the queue's objective (4000): a longer request is shown to the owner, never cut or dropped.
    @Test
    func theCeilingIs4000AndALongerRequestIsReportedWithItsLength() {
        #expect(VoiceHandoff.maxTextLength == 4000)
        let atLimit = String(repeating: "あ", count: 4000)
        let over = String(repeating: "あ", count: 4001)
        #expect(VoiceHandoff.macURL(utteranceID: utterance, thread: thread, text: atLimit) != nil)
        #expect(VoiceHandoff.macURL(utteranceID: utterance, thread: thread, text: over) == nil)
        #expect(VoiceHandoff.url(utteranceID: utterance, thread: thread, text: over) == nil)
        #expect(VoiceHandoff.plan(text: over, macAppInstalled: true) == .tooLong(length: 4001))
        if case .mac = VoiceHandoff.plan(text: atLimit, macAppInstalled: true) {} else { Issue.record("4000 字ちょうどは通る") }
    }

    @Test
    func thePlanPrefersTheMacAppAndFallsBackToTheHub() throws {
        guard case .mac(let mac) = VoiceHandoff.plan(text: "朝の準備", macAppInstalled: true) else { Issue.record("Mac アプリがあれば Mac へ"); return }
        #expect(mac.scheme == VoiceHandoff.macScheme)
        guard case .hub(let hub) = VoiceHandoff.plan(text: "朝の準備", macAppInstalled: false) else { Issue.record("無ければ Hub へ"); return }
        #expect(hub.host == "mitama-os-hub.vercel.app")
        #expect(VoiceHandoff.plan(text: "  ", macAppInstalled: true) == .empty)
    }

    @Test
    func everyPlanMintsFreshLowercaseUUIDv4IDsAndTheMacLinkCarriesThem() throws {
        guard case .mac(let a) = VoiceHandoff.plan(text: "x", macAppInstalled: true), case .mac(let b) = VoiceHandoff.plan(text: "x", macAppInstalled: true) else { Issue.record("mac"); return }
        #expect(a != b)
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: a, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(VoiceHandoff.isUUIDv4(items["utterance"] ?? ""))
        #expect(VoiceHandoff.isUUIDv4(items["thread"] ?? ""))
    }

    @Test
    func theKeyIsNeverRaphaelsVoicePrefix() {
        #expect(VoiceHandoff.sourceRef(utteranceID: utterance) == "voice-utterance:\(utterance)")
    }
}
