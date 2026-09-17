import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Conversation log")
struct ConversationLogTests {
    private func line(_ json: String) -> Data { Data(json.utf8) }

    @Test("A typed prompt becomes a user entry")
    func userString() {
        let entries = ConversationLog.entries(fromLine: line(#"{"type":"user","uuid":"u1","timestamp":"2026-09-17T06:33:12.563Z","message":{"role":"user","content":"  直して  "}}"#))
        #expect(entries.count == 1)
        #expect(entries[0].kind == .user)
        #expect(entries[0].text == "直して")
        #expect(entries[0].timestamp != nil)
    }

    @Test("Harness-injected user text, meta and sidechain lines are left out")
    func injectedTextIsSkipped() {
        #expect(ConversationLog.entries(fromLine: line(#"{"type":"user","message":{"content":"<system-reminder>x</system-reminder>"}}"#)).isEmpty)
        #expect(ConversationLog.entries(fromLine: line(#"{"type":"user","message":{"content":"<command-name>/clear</command-name>"}}"#)).isEmpty)
        #expect(ConversationLog.entries(fromLine: line(#"{"type":"user","isMeta":true,"message":{"content":"hi"}}"#)).isEmpty)
        #expect(ConversationLog.entries(fromLine: line(#"{"type":"assistant","isSidechain":true,"message":{"content":[{"type":"text","text":"sub"}]}}"#)).isEmpty)
    }

    @Test("What a tool returned never appears")
    func toolResultsAreSkipped() {
        let entries = ConversationLog.entries(fromLine: line(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t","content":"SECRET=abc"}]}}"#))
        #expect(entries.isEmpty)
    }

    @Test("Assistant text and tool calls come through; thinking and inputs do not")
    func assistantParts() {
        let entries = ConversationLog.entries(fromLine: line(#"{"type":"assistant","uuid":"a1","message":{"content":[{"type":"thinking","thinking":"hmm"},{"type":"text","text":"やります"},{"type":"tool_use","name":"Edit","input":{"file_path":"/Users/x/Secret/Plan.swift","old_string":"a"}},{"type":"tool_use","name":"Bash","input":{"command":"curl https://x?token=1"}}]}}"#))
        #expect(entries.map(\.kind) == [
            .assistant,
            .tool(name: "Edit", target: "Plan.swift"),
            .tool(name: "Bash", target: nil),
        ])
        #expect(entries[0].text == "やります")
        #expect(!entries.contains { $0.text.contains("token") || $0.text.contains("hmm") })
        #expect(Set(entries.map(\.id)).count == 3)
    }

    @Test("Broken and unrelated lines are skipped without taking the rest down")
    func brokenLines() {
        let data = Data("""
        {not json
        {"type":"attachment","attachment":{}}
        {"type":"user","message":{"content":"ok"}}
        """.utf8)
        let entries = ConversationLog.entries(fromTail: data, startsMidFile: false, limit: 10)
        #expect(entries.map(\.text) == ["ok"])
    }

    @Test("A chunk from mid-file drops its partial first line and keeps the newest entries")
    func tailReading() {
        let data = Data("""
        ntent":"fragment"}}
        {"type":"user","message":{"content":"one"}}
        {"type":"user","message":{"content":"two"}}
        {"type":"user","message":{"content":"three"}}
        """.utf8)
        let entries = ConversationLog.entries(fromTail: data, startsMidFile: true, limit: 2)
        #expect(entries.map(\.text) == ["two", "three"])
    }

    @Test("Days split on the calendar date, runs split on who is speaking")
    func daysAndRuns() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let day1 = Date(timeIntervalSince1970: 1_758_000_000)
        let day2 = day1.addingTimeInterval(86_400)
        let entries = [
            ConversationEntry(id: "1", kind: .user, text: "a", timestamp: day1),
            ConversationEntry(id: "2", kind: .assistant, text: "b", timestamp: day1),
            ConversationEntry(id: "3", kind: .tool(name: "Edit", target: nil), text: "", timestamp: day1),
            ConversationEntry(id: "4", kind: .assistant, text: "c", timestamp: nil),
            ConversationEntry(id: "5", kind: .user, text: "d", timestamp: day2),
        ]
        let days = ConversationLog.days(entries, calendar: calendar)
        #expect(days.count == 2)
        #expect(days[0].runs.map(\.isFromUser) == [true, false])
        #expect(days[0].runs[1].entries.map(\.id) == ["2", "3", "4"])
        #expect(days[1].runs.map { $0.entries.map(\.id) } == [["5"]])
        #expect(ConversationLog.days([]).isEmpty)
    }
}
