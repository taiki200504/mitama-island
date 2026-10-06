import Foundation

public enum ClaudeQuestionSiblingGate {
    private static let maxTailBytes: UInt64 = 1_048_576

    public static func hasSiblingQuestion(transcriptPath: String, toolUseID: String) -> Bool {
        guard !transcriptPath.isEmpty, !toolUseID.isEmpty else { return false }

        do {
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: transcriptPath))
            defer { try? handle.close() }

            let fileSize = try handle.seekToEnd()
            let offset = fileSize > maxTailBytes ? fileSize - maxTailBytes : 0
            try handle.seek(toOffset: offset)
            let data = try handle.readToEnd() ?? Data()
            guard !data.isEmpty else { return false }

            var bytes = data
            if offset > 0, let newline = bytes.firstIndex(of: 0x0A) {
                bytes.removeSubrange(...newline)
            } else if offset > 0 {
                return false
            }

            guard let text = String(data: bytes, encoding: .utf8) else { return false }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true)

            var targetMessageID: String?
            var toolUsesByMessageID: [String: [String]] = [:]

            // Called on every PreToolUse: only decode the lines that can matter.
            for line in lines where line.contains(toolUseID) || line.contains("AskUserQuestion") {
                guard let lineData = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      object["type"] as? String == "assistant",
                      let message = object["message"] as? [String: Any],
                      let messageID = message["id"] as? String,
                      let content = message["content"] as? [Any] else {
                    continue
                }

                for item in content {
                    guard let block = item as? [String: Any],
                          block["type"] as? String == "tool_use" else {
                        continue
                    }
                    guard let name = block["name"] as? String else { continue }
                    toolUsesByMessageID[messageID, default: []].append(name)
                    if block["id"] as? String == toolUseID {
                        targetMessageID = messageID
                    }
                }
            }

            guard let targetMessageID else { return false }
            return toolUsesByMessageID[targetMessageID]?.contains("AskUserQuestion") == true
        } catch {
            return false
        }
    }
}
