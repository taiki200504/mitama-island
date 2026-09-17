import Foundation
import Testing
@testable import OpenIslandCore

struct ConversationLogReaderTests {
    let tempDir = FileManager.default.temporaryDirectory

    @Test("Parse basic user-assistant exchange")
    func parseBasicExchange() throws {
        let jsonl = """
{"role":"user","type":"text","content":"hello","timestamp":1609459200}
{"role":"assistant","type":"text","content":"Hi there!","timestamp":1609459210}
"""
        let file = tempDir.appendingPathComponent(UUID().uuidString + ".jsonl")
        try jsonl.write(toFile: file.path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let messages = ConversationLogReader.readMessages(from: file.path)
        #expect(messages.count == 2)
        #expect(messages[0].role == .user)
        #expect(messages[0].text == "hello")
        #expect(messages[1].role == .assistant)
        #expect(messages[1].text == "Hi there!")
    }

    @Test("Skip tool_result entries (privacy)")
    func skipToolResults() throws {
        let jsonl = """
{"role":"user","type":"text","content":"edit this file","timestamp":1609459200}
{"role":"assistant","type":"tool_use","tool_name":"Edit","timestamp":1609459210}
{"role":"assistant","type":"tool_result","content":"file contents here","timestamp":1609459220}
{"role":"assistant","type":"text","content":"Done!","timestamp":1609459230}
"""
        let file = tempDir.appendingPathComponent(UUID().uuidString + ".jsonl")
        try jsonl.write(toFile: file.path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let messages = ConversationLogReader.readMessages(from: file.path)
        #expect(messages.count == 3) // user, tool_use, assistant
        #expect(messages.filter { $0.text.contains("file contents") }.isEmpty)
    }

    @Test("Summarize tool_use as one-liner")
    func toolUseSummary() throws {
        let jsonl = """
{"role":"assistant","type":"tool_use","tool_name":"Read","timestamp":1609459210}
"""
        let file = tempDir.appendingPathComponent(UUID().uuidString + ".jsonl")
        try jsonl.write(toFile: file.path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let messages = ConversationLogReader.readMessages(from: file.path)
        #expect(messages.count == 1)
        #expect(messages[0].toolSummary == "tool: Read")
    }

    @Test("Handle ISO8601 and Unix timestamps")
    func parseTimestamps() throws {
        let jsonl = """
{"role":"user","type":"text","content":"msg1","timestamp":"2021-01-01T00:00:00Z"}
{"role":"user","type":"text","content":"msg2","timestamp":1609459200}
"""
        let file = tempDir.appendingPathComponent(UUID().uuidString + ".jsonl")
        try jsonl.write(toFile: file.path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let messages = ConversationLogReader.readMessages(from: file.path)
        #expect(messages.count == 2)
        #expect(messages[0].timestamp.timeIntervalSince1970 == 1609459200)
        #expect(messages[1].timestamp.timeIntervalSince1970 == 1609459200)
    }

    @Test("Return empty for nonexistent file")
    func nonexistentFile() {
        let messages = ConversationLogReader.readMessages(from: "/nonexistent/path.jsonl")
        #expect(messages.isEmpty)
    }

    @Test("Group consecutive messages by role")
    func groupByRole() throws {
        let msg1 = ConversationMessage(role: .user, text: "a", timestamp: Date())
        let msg2 = ConversationMessage(role: .user, text: "b", timestamp: Date())
        let msg3 = ConversationMessage(role: .assistant, text: "c", timestamp: Date())
        let msg4 = ConversationMessage(role: .assistant, text: "d", timestamp: Date())

        let messages = [msg1, msg2, msg3, msg4]
        let groups = messages.groupedByConsecutiveRole()

        #expect(groups.count == 2)
        #expect(groups[0].role == .user)
        #expect(groups[0].messages.count == 2)
        #expect(groups[1].role == .assistant)
        #expect(groups[1].messages.count == 2)
    }

    @Test("Find day boundaries")
    func dayBoundaries() throws {
        let calendar = Calendar.current
        let day1 = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Date()) ?? Date()
        let day2 = calendar.date(byAdding: .day, value: 1, to: day1) ?? Date()

        let msg1 = ConversationMessage(role: .user, text: "day1", timestamp: day1)
        let msg2 = ConversationMessage(role: .assistant, text: "day1_reply", timestamp: day1)
        let msg3 = ConversationMessage(role: .user, text: "day2", timestamp: day2)

        let messages = [msg1, msg2, msg3]
        let boundaries = messages.dayBoundaries()

        #expect(boundaries.count == 1)
        #expect(boundaries[0].messageIndex == 2)
    }
}
