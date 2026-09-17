import Foundation

/// One thing said or done in a session, as the conversation log shows it.
///
/// Deliberately thin. What a tool *returned* — file contents, command output,
/// search results — never makes it this far: the log is on a screen other
/// people can see, and the island is a glance, not a second terminal.
public struct ConversationEntry: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Something the person typed.
        case user
        /// Something the agent said back.
        case assistant
        /// A tool the agent reached for, named but never opened up.
        case tool(name: String, target: String?)
    }

    public let id: String
    public let kind: Kind
    /// Empty for `.tool`.
    public let text: String
    public let timestamp: Date?

    public init(id: String, kind: Kind, text: String, timestamp: Date?) {
        self.id = id
        self.kind = kind
        self.text = text
        self.timestamp = timestamp
    }

    /// Which side of the conversation this sits on. Tools are the agent's.
    public var isFromUser: Bool { kind == .user }
}

/// Consecutive entries from the same side, drawn as one run of bubbles.
public struct ConversationRun: Equatable, Identifiable, Sendable {
    public let isFromUser: Bool
    public let entries: [ConversationEntry]
    public var id: String { entries.first?.id ?? "" }
}

/// One calendar day of the log, headed by a date chip.
public struct ConversationDay: Equatable, Identifiable, Sendable {
    /// Start of the day, or nil for entries with no timestamp at all.
    public let day: Date?
    public let runs: [ConversationRun]
    public var id: String { runs.first?.id ?? "" }
}

/// Reads Claude Code's transcript JSONL into `ConversationEntry` values.
///
/// Pure apart from `read(path:)`, so every rule about what is shown and what
/// is kept out can be checked against literal lines.
public enum ConversationLog {
    /// Reads at most `maxBytes` from the end of the transcript and returns the
    /// last `limit` entries. Nothing is read from the front of a long file:
    /// the end is what anyone opening the log wants to see.
    public static func read(path: String, maxBytes: Int = 4 * 1024 * 1024, limit: Int = 200) -> [ConversationEntry] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else { return [] }
        let offset = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd() else { return [] }
        return entries(fromTail: data, startsMidFile: offset > 0, limit: limit)
    }

    /// Parses a chunk read from the end of a transcript. When the chunk starts
    /// part-way through the file its first line is a fragment and is dropped.
    public static func entries(fromTail data: Data, startsMidFile: Bool, limit: Int) -> [ConversationEntry] {
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if startsMidFile, !lines.isEmpty { lines.removeFirst() }
        let parsed = lines.flatMap { entries(fromLine: Data($0)) }
        return Array(parsed.suffix(max(limit, 0)))
    }

    /// Everything one transcript line contributes — usually nothing (hook
    /// attachments, metadata, tool results, thinking), sometimes a message,
    /// sometimes one entry per tool call.
    public static func entries(fromLine line: Data) -> [ConversationEntry] {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = object["type"] as? String,
              object["isSidechain"] as? Bool != true,
              object["isMeta"] as? Bool != true,
              let message = object["message"] as? [String: Any] else {
            return []
        }

        let uuid = object["uuid"] as? String ?? UUID().uuidString
        let timestamp = (object["timestamp"] as? String).flatMap(parseTimestamp)

        switch type {
        case "user":
            let text: String
            if let string = message["content"] as? String {
                text = string
            } else if let parts = message["content"] as? [[String: Any]] {
                // tool_result parts are what tools sent back; only typed text counts.
                text = parts
                    .filter { $0["type"] as? String == "text" }
                    .compactMap { $0["text"] as? String }
                    .joined(separator: "\n")
            } else {
                return []
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !isInjected(trimmed) else { return [] }
            return [ConversationEntry(id: uuid, kind: .user, text: trimmed, timestamp: timestamp)]

        case "assistant":
            guard let parts = message["content"] as? [[String: Any]] else { return [] }
            var result: [ConversationEntry] = []
            for (index, part) in parts.enumerated() {
                switch part["type"] as? String {
                case "text":
                    let text = (part["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    result.append(ConversationEntry(id: "\(uuid)#\(index)", kind: .assistant, text: text, timestamp: timestamp))
                case "tool_use":
                    guard let name = part["name"] as? String else { continue }
                    let input = part["input"] as? [String: Any]
                    result.append(ConversationEntry(
                        id: "\(uuid)#\(index)",
                        kind: .tool(name: name, target: toolTarget(input)),
                        text: "",
                        timestamp: timestamp
                    ))
                default:
                    // thinking, and anything newer we don't know how to show safely.
                    continue
                }
            }
            return result

        default:
            return []
        }
    }

    /// Groups entries into days, and each day into runs from one side.
    public static func days(_ entries: [ConversationEntry], calendar: Calendar = .current) -> [ConversationDay] {
        var days: [ConversationDay] = []
        var currentDay: Date?? = nil
        var runs: [ConversationRun] = []
        var run: [ConversationEntry] = []

        func closeRun() {
            guard let first = run.first else { return }
            runs.append(ConversationRun(isFromUser: first.isFromUser, entries: run))
            run = []
        }
        func closeDay() {
            closeRun()
            if let currentDay, !runs.isEmpty {
                days.append(ConversationDay(day: currentDay, runs: runs))
            }
            runs = []
        }

        for entry in entries {
            // An entry with no timestamp stays on whatever day it follows.
            let day = entry.timestamp.map { calendar.startOfDay(for: $0) } ?? (currentDay ?? nil)
            if currentDay == nil || currentDay! != day {
                closeDay()
                currentDay = .some(day)
            }
            if let last = run.last, last.isFromUser != entry.isFromUser {
                closeRun()
            }
            run.append(entry)
        }
        closeDay()
        return days
    }

    // MARK: - Private

    /// Text the harness put in the user's turn rather than the person: system
    /// reminders, slash-command echoes, task notifications, local command output.
    private static func isInjected(_ text: String) -> Bool {
        text.hasPrefix("<") || text.hasPrefix("Caveat:")
    }

    /// Just the file's name, when a tool names one. Never a command line, a
    /// search pattern or a URL — those can carry anything.
    private static func toolTarget(_ input: [String: Any]?) -> String? {
        guard let input else { return nil }
        for key in ["file_path", "notebook_path", "path"] {
            if let path = input[key] as? String, !path.isEmpty {
                return (path as NSString).lastPathComponent
            }
        }
        return nil
    }

    private static func parseTimestamp(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}
