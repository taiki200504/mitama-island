import Foundation

/// Statistics about tool use and achievements from a transcript.
public struct TranscriptStats: Equatable, Sendable {
    /// Number of file edits (Edit, Write, MultiEdit, NotebookEdit tools).
    public var editCount: Int = 0

    /// Number of shell commands executed (Bash, Run tools).
    public var commandCount: Int = 0

    /// Number of tasks created / completed (Task, TodoWrite tools).
    public var taskCount: Int = 0

    /// Number of subagents spawned / tasks delegated.
    public var delegationCount: Int = 0

    public init(editCount: Int = 0, commandCount: Int = 0, taskCount: Int = 0, delegationCount: Int = 0) {
        self.editCount = editCount
        self.commandCount = commandCount
        self.taskCount = taskCount
        self.delegationCount = delegationCount
    }

    /// Returns a compact one-line summary (e.g., "編集 5・コマンド 12・タスク 2/3").
    /// Omits 0 entries. Returns `nil` if all counts are 0.
    public func formatSummary() -> String? {
        var parts: [String] = []

        if editCount > 0 {
            parts.append("edit \(editCount)")
        }
        if commandCount > 0 {
            parts.append("cmd \(commandCount)")
        }
        if taskCount > 0 {
            parts.append("task \(taskCount)")
        }
        if delegationCount > 0 {
            parts.append("agent \(delegationCount)")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Cache key and value for transcript stats.
public struct TranscriptStatsCache: Sendable {
    public let fileSize: Int
    public let modificationTime: Date
    public let stats: TranscriptStats

    public init(fileSize: Int, modificationTime: Date, stats: TranscriptStats) {
        self.fileSize = fileSize
        self.modificationTime = modificationTime
        self.stats = stats
    }

    /// Returns whether this cache is still valid for the given file attributes.
    public func isValid(fileSize: Int, modificationTime: Date) -> Bool {
        self.fileSize == fileSize && self.modificationTime == modificationTime
    }
}

/// Parses transcript JSONL to extract tool usage statistics.
public struct TranscriptStatsParser: Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Extracts statistics from a transcript file.
    /// Returns nil if the file does not exist or cannot be read.
    public func extractStats(from transcriptPath: String) -> TranscriptStats? {
        let fileURL = URL(fileURLWithPath: transcriptPath)

        guard fileManager.fileExists(atPath: transcriptPath),
              let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? fileHandle.close() }

        var stats = TranscriptStats()
        let processLine: (String) -> Void = { line in
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            if let type = object["type"] as? String {
                // Hook-generated events
                if type == "taskCreated" || type == "taskCompleted" {
                    stats.taskCount += 1
                    return
                }
            }

            // Message payloads: scan tool_use blocks
            if let message = object["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    if let blockType = block["type"] as? String,
                       let toolName = block["name"] as? String {
                        switch blockType {
                        case "tool_use":
                            categorizeToolUse(toolName, &stats)
                        default:
                            break
                        }
                    }
                }
            }
        }

        streamLines(from: fileHandle, into: processLine)

        return stats
    }

    /// Categorizes tool use by name and increments the appropriate counter.
    private func categorizeToolUse(_ toolName: String, _ stats: inout TranscriptStats) {
        let lowerName = toolName.lowercased()

        // Edit tools
        if lowerName.contains("edit") || lowerName.contains("write") ||
            lowerName.contains("multiEdit") || lowerName.contains("notebookEdit") {
            stats.editCount += 1
        }
        // Command tools
        else if lowerName.contains("bash") || lowerName.contains("run") ||
            lowerName.contains("shell") || lowerName.contains("command") {
            stats.commandCount += 1
        }
        // Task tools
        else if lowerName.contains("task") || lowerName.contains("todo") {
            stats.taskCount += 1
        }
        // Delegation tools
        else if lowerName.contains("agent") || lowerName.contains("spawn") {
            stats.delegationCount += 1
        }
    }

    /// Streams lines from a file handle, processing each complete line.
    private func streamLines(from fileHandle: FileHandle, into handler: (String) -> Void) {
        let chunkSize = 64 * 1_024
        var buffer = Data()

        while let chunk = try? fileHandle.read(upToCount: chunkSize), !chunk.isEmpty {
            buffer.append(chunk)
            for line in extractCompleteLines(from: &buffer) {
                handler(line)
            }
        }

        // Honor a final line without a trailing newline
        if !buffer.isEmpty,
           let trailing = String(data: buffer, encoding: .utf8),
           !trailing.isEmpty {
            handler(trailing)
        }
    }

    /// Extracts complete lines (ending with \n) from the buffer.
    /// Mutates the buffer, removing extracted lines.
    private func extractCompleteLines(from buffer: inout Data) -> [String] {
        let newline = UInt8(ascii: "\n")
        var lines: [String] = []

        while let newlineIndex = buffer.firstIndex(of: newline) {
            let lineData = buffer.prefix(upTo: newlineIndex)
            buffer.removeSubrange(...newlineIndex)
            guard !lineData.isEmpty else { continue }
            lines.append(String(decoding: lineData, as: UTF8.self))
        }

        return lines
    }
}
