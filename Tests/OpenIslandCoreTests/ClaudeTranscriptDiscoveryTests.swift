import Foundation
import Testing
@testable import OpenIslandCore

struct ClaudeTranscriptDiscoveryTests {
    private func makeTranscriptRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("open-island-transcripts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeTranscript(
        at root: URL,
        project: String,
        sessionID: String,
        lines: [String]
    ) throws -> URL {
        let projectDirectory = root.appendingPathComponent(project, isDirectory: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        let fileURL = projectDirectory.appendingPathComponent("\(sessionID).jsonl")
        try lines.joined(separator: "\n").appending("\n").write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func userLine(_ text: String, cwd: String, timestamp: String) -> String {
        let object: [String: Any] = [
            "cwd": cwd,
            "timestamp": timestamp,
            "message": ["role": "user", "content": text],
        ]
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private func assistantLine(_ text: String, cwd: String, timestamp: String) -> String {
        let object: [String: Any] = [
            "cwd": cwd,
            "timestamp": timestamp,
            "message": [
                "role": "assistant",
                "model": "claude-opus-5",
                "content": [["type": "text", "text": text]],
            ],
        ]
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    @Test
    func parsesSmallTranscriptEndToEnd() throws {
        let root = try makeTranscriptRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try writeTranscript(
            at: root,
            project: "-Users-test-project",
            sessionID: "11111111-1111-1111-1111-111111111111",
            lines: [
                userLine("最初の依頼", cwd: "/Users/test/project", timestamp: "2026-07-31T10:00:00.000Z"),
                assistantLine("進めます", cwd: "/Users/test/project", timestamp: "2026-07-31T10:00:01.000Z"),
                userLine("最後の依頼", cwd: "/Users/test/project", timestamp: "2026-07-31T10:00:02.000Z"),
            ]
        )

        let discovery = ClaudeTranscriptDiscovery(rootURL: root, maxAge: .greatestFiniteMagnitude)
        let sessions = discovery.discoverRecentSessions()

        #expect(sessions.count == 1)
        let metadata = try #require(sessions.first?.claudeMetadata)
        #expect(metadata.initialUserPrompt == "最初の依頼")
        #expect(metadata.lastUserPrompt == "最後の依頼")
        #expect(metadata.lastAssistantMessage == "進めます")
    }

    @Test
    func keepsBothEndsOfATranscriptTooLargeToParseWhole() throws {
        let root = try makeTranscriptRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let cwd = "/Users/test/project"
        // Padding sized so the file lands well past the 2MB full-parse limit,
        // forcing the head+tail path.
        let padding = String(repeating: "x", count: 4_096)
        var lines = [userLine("最初の依頼", cwd: cwd, timestamp: "2026-07-31T10:00:00.000Z")]
        for index in 0..<800 {
            lines.append(assistantLine("中間 \(index) \(padding)", cwd: cwd, timestamp: "2026-07-31T10:00:01.000Z"))
        }
        lines.append(userLine("最後の依頼", cwd: cwd, timestamp: "2026-07-31T10:30:00.000Z"))
        lines.append(assistantLine("完了しました", cwd: cwd, timestamp: "2026-07-31T10:30:01.000Z"))

        let fileURL = try writeTranscript(
            at: root,
            project: "-Users-test-project",
            sessionID: "22222222-2222-2222-2222-222222222222",
            lines: lines
        )
        let size = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int ?? 0
        #expect(size > 2 * 1_024 * 1_024)

        let discovery = ClaudeTranscriptDiscovery(rootURL: root, maxAge: .greatestFiniteMagnitude)
        let sessions = discovery.discoverRecentSessions()

        let metadata = try #require(sessions.first?.claudeMetadata)
        // Head gives the opening prompt, tail gives the current state.
        #expect(metadata.initialUserPrompt == "最初の依頼")
        #expect(metadata.lastUserPrompt == "最後の依頼")
        #expect(metadata.lastAssistantMessage == "完了しました")
    }

    @Test
    func readsTimestampsWithAndWithoutFractionalSeconds() {
        let discovery = ClaudeTranscriptDiscovery()

        #expect(discovery.parseTimestamp("2026-07-31T10:00:00.123Z") != nil)
        #expect(discovery.parseTimestamp("2026-07-31T10:00:00Z") != nil)
        #expect(discovery.parseTimestamp("not a timestamp") == nil)
    }
}
