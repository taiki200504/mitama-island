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
