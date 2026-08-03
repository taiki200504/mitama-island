import Foundation
import Testing
@testable import OpenIslandCore

struct MitamaNotificationsTests {
    @Test
    func parsesQuotedExportedAndCommentedEnvLines() {
        let env = MitamaEnvironment.parse(envFileContents: """
        # mitama-os
        SUPABASE_URL="https://example.supabase.co"
        export SUPABASE_KEY='secret-value'
        UNRELATED=1
        """)

        #expect(env?.url.absoluteString == "https://example.supabase.co")
        #expect(env?.apiKey == "secret-value")
    }

    @Test
    func returnsNilWhenCredentialsAreIncomplete() {
        #expect(MitamaEnvironment.parse(envFileContents: "SUPABASE_URL=https://example.supabase.co") == nil)
        #expect(MitamaEnvironment.parse(envFileContents: "") == nil)
    }

    @Test
    func decodesNotificationRowsWithAndWithoutFractionalSeconds() throws {
        let json = """
        [
          {"id": 1, "level": "urgent", "title": "承認待ち", "body": "本文", "created_at": "2026-08-01T02:15:00.123456+00:00"},
          {"id": 2, "level": "homework", "title": "宿題", "body": "本文", "created_at": "2026-08-01T02:15:00+00:00"}
        ]
        """
        // Exercise the same decoder the client uses.
        let client = MitamaNotificationClient(
            environment: MitamaEnvironment(url: URL(string: "https://example.supabase.co")!, apiKey: "k")
        )
        let rows = try client.decodeForTests([MitamaNotification].self, from: Data(json.utf8))

        #expect(rows.count == 2)
        #expect(rows[0].level == .urgent)
        #expect(rows[1].level == .homework)
        #expect(rows[0].createdAt < rows[1].createdAt.addingTimeInterval(1))
    }

    @Test
    func onlyUrgentAndHomeworkCountAsActionable() {
        #expect(MitamaNotification.Level.actionable == [.urgent, .homework])
    }
}
