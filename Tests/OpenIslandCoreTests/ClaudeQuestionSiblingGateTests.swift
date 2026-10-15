import Foundation
import Testing
@testable import OpenIslandCore

struct ClaudeQuestionSiblingGateTests {
    @Test
    func sameMessageWithBashAndAskUserQuestionReturnsTrue() throws {
        let url = try writeTranscript("""
        {"type":"assistant","message":{"id":"msg_1","content":[{"type":"tool_use","id":"toolu_bash","name":"Bash"}]}}
        {"type":"assistant","message":{"id":"msg_1","content":[{"type":"tool_use","id":"toolu_question","name":"AskUserQuestion"}]}}
        """)

        #expect(ClaudeQuestionSiblingGate.hasSiblingQuestion(transcriptPath: url.path, toolUseID: "toolu_bash"))
    }

    @Test
    func messageWithoutQuestionReturnsFalse() throws {
        let url = try writeTranscript("""
        {"type":"assistant","message":{"id":"msg_1","content":[{"type":"tool_use","id":"toolu_bash","name":"Bash"}]}}
        {"type":"assistant","message":{"id":"msg_1","content":[{"type":"tool_use","id":"toolu_edit","name":"Edit"}]}}
        """)

        #expect(!ClaudeQuestionSiblingGate.hasSiblingQuestion(transcriptPath: url.path, toolUseID: "toolu_bash"))
    }

    @Test
    func questionInDifferentMessageReturnsFalse() throws {
        let url = try writeTranscript("""
        {"type":"assistant","message":{"id":"msg_1","content":[{"type":"tool_use","id":"toolu_bash","name":"Bash"}]}}
        {"type":"assistant","message":{"id":"msg_2","content":[{"type":"tool_use","id":"toolu_question","name":"AskUserQuestion"}]}}
        """)

        #expect(!ClaudeQuestionSiblingGate.hasSiblingQuestion(transcriptPath: url.path, toolUseID: "toolu_bash"))
    }

    @Test
    func missingFileReturnsFalse() {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing.jsonl")
            .path

        #expect(!ClaudeQuestionSiblingGate.hasSiblingQuestion(transcriptPath: path, toolUseID: "toolu_bash"))
    }

    @Test
    func bridgeServerDeniesNonQuestionSiblingTool() throws {
        let transcriptURL = try writeTranscript("""
        {"type":"assistant","message":{"id":"msg_1","content":[{"type":"tool_use","id":"toolu_bash","name":"Bash"}]}}
        {"type":"assistant","message":{"id":"msg_1","content":[{"type":"tool_use","id":"toolu_question","name":"AskUserQuestion"}]}}
        """)
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let payload = ClaudeHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .preToolUse,
            sessionID: "session-1",
            transcriptPath: transcriptURL.path,
            toolName: "Bash",
            toolInput: .object(["command": .string("date")]),
            toolUseID: "toolu_bash"
        )
        let response = try BridgeCommandClient(socketURL: socketURL).send(.processClaudeHook(payload))

        guard case let .claudeHookDirective(.preToolUse(directive)) = response else {
            Issue.record("Expected preToolUse directive")
            return
        }
        #expect(directive.permissionDecision == .deny)
        #expect(directive.permissionDecisionReason?.contains("same message as AskUserQuestion") == true)
    }

    private func writeTranscript(_ contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-question-sibling-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("transcript.jsonl")
        try (contents + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
