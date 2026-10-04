import Foundation
import Testing
@testable import OpenIslandCore

struct CodexSubagentIdentityTests {
    private let parent = "11111111-1111-4111-8111-111111111111"
    private let child = "22222222-2222-4222-8222-222222222222"
    private func line(source: [String: Any]) throws -> String {
        let object: [String: Any] = ["type": "session_meta", "payload": [
            "id": child, "cwd": "/fixture", "source": source
        ]]
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    @Test func formalParentSurvivesDiscoveryReducerPersistenceAndLaterMetadata() throws {
        let meta = try line(source: ["subagent": ["thread_spawn": ["parent_thread_id": parent]]])
        let snapshot = CodexRolloutReducer.snapshot(for: [meta])
        #expect(snapshot.metadata.parentThreadID == parent)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try (meta + "\n").write(to: root.appendingPathComponent("rollout-child.jsonl"), atomically: true, encoding: .utf8)
        let record = try #require(CodexRolloutDiscovery(rootURL: root).discoverRecentSessions().first)
        #expect(record.codexMetadata?.parentThreadID == parent)
        let roundtrip = try JSONDecoder().decode(CodexTrackedSessionRecord.self, from: JSONEncoder().encode(record))
        #expect(roundtrip.codexMetadata?.parentThreadID == parent)
        var state = SessionState(sessions: [roundtrip.session])
        state.apply(.sessionMetadataUpdated(SessionMetadataUpdated(sessionID: child,
            codexMetadata: CodexSessionMetadata(currentTool: "exec_command"), timestamp: .now)))
        #expect(state.session(id: child)?.codexMetadata?.parentThreadID == parent)
    }

    @Test func unknownMalformedAndLegacyDoNotEstablishParent() throws {
        for source: [String: Any] in [
            ["parent_thread_id": parent],
            ["subagent": ["other": ["parent_thread_id": parent]]],
            ["subagent": ["thread_spawn": ["parent_thread_id": "not-an-id"]]],
            ["subagent": ["thread_spawn": ["parent_thread_id": child]]]
        ] {
            #expect(CodexRolloutReducer.snapshot(for: [try line(source: source)]).metadata.parentThreadID == nil)
        }
        let legacy = try JSONDecoder().decode(CodexSessionMetadata.self, from: Data("{}".utf8))
        #expect(legacy.parentThreadID == nil)
    }
}
