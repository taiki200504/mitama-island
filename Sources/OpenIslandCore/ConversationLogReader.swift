import Foundation

/// Reads Claude Code transcript JSONL files and extracts user/assistant messages.
/// Tool results and intermediate data are never exposed — only text and tool summaries.
public enum ConversationLogReader {
    /// Parse a Claude Code transcript JSONL file from the given path.
    /// Reads up to `maxMessages` from the end of the file (tail read).
    /// Skips malformed lines and tool_result entries.
    ///
    /// Thread-safe; runs on the calling thread. For large files, consider dispatching to a background queue.
    ///
    /// - Parameters:
    ///   - path: File system path to a `.jsonl` transcript file
    ///   - maxMessages: Maximum messages to return (default: 200). File is read from the tail.
    ///   - maxFileSize: Maximum bytes to read from the end of the file (default: 8MB)
    ///
    /// - Returns: Array of ConversationMessage in chronological order, or empty if file cannot be read
    public static func readMessages(
        from path: String,
        maxMessages: Int = 200,
        maxFileSize: Int = 8 * 1024 * 1024
    ) -> [ConversationMessage] {
        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return [] }

        do {
            let fileHandle = try FileHandle(forReadingFrom: fileURL)
            defer { try? fileHandle.close() }

            // Tail-read strategy: seek to end and read backwards
            let fileSize = try fileHandle.seekToEnd()
            let readSize = min(Int(fileSize), maxFileSize)
            let seekOffset = max(0, Int(fileSize) - readSize)

            try fileHandle.seek(toOffset: UInt64(seekOffset))
            let data = try fileHandle.readToEndOfFile()

            guard let content = String(data: data, encoding: .utf8) else { return [] }

            let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
            var messages: [ConversationMessage] = []

            for line in lines {
                guard let message = parseJSONLLine(String(line)) else { continue }
                messages.append(message)
                if messages.count >= maxMessages { break }
            }

            // Reverse to chronological order (tail-read puts newest first)
            return messages.reversed()
        } catch {
            return []
        }
    }

    // MARK: - Private Parsing

    private static func parseJSONLLine(_ line: String) -> ConversationMessage? {
        guard let jsonData = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }

        // Extract role (must be "user" or "assistant")
        guard let role = json["role"] as? String else { return nil }
        guard let roleEnum = ConversationMessage.Role(rawValue: role) else { return nil }

        // Extract timestamp
        let timestamp: Date
        if let timestampDouble = json["timestamp"] as? TimeInterval {
            timestamp = Date(timeIntervalSince1970: timestampDouble)
        } else if let timestampString = json["timestamp"] as? String {
            let formatter = ISO8601DateFormatter()
            timestamp = formatter.date(from: timestampString) ?? Date()
        } else {
            timestamp = Date()
        }

        // Extract text content — skip tool_result entries
        guard let contentType = json["type"] as? String else { return nil }

        // Only text messages and tool_use summaries are shown
        var text: String?
        var toolSummary: String?

        if contentType == "text", let content = json["content"] as? String {
            text = content
        } else if contentType == "tool_use", let toolName = json["tool_name"] as? String {
            // Summarize the tool call as a single line (input/output never shown)
            toolSummary = "tool: \(toolName)"
        } else if contentType == "tool_result" {
            // Never extract or display tool results
            return nil
        }

        // Accept either text or tool_summary, but not empty messages
        if let text = text, !text.trimmingCharacters(in: .whitespaces).isEmpty {
            return ConversationMessage(
                role: roleEnum,
                text: text,
                timestamp: timestamp,
                toolSummary: toolSummary
            )
        } else if let toolSummary = toolSummary {
            return ConversationMessage(
                role: roleEnum,
                text: "",
                timestamp: timestamp,
                toolSummary: toolSummary
            )
        }

        return nil
    }
}
