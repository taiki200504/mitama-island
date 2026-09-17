import Foundation

/// A single message in a Claude Code conversation transcript.
public struct ConversationMessage: Equatable, Sendable, Identifiable {
    public let id: String

    /// Either "user" or "assistant".
    public let role: Role
    /// The message text content. Does not include tool results or intermediate data.
    public let text: String
    /// When this message was logged.
    public let timestamp: Date
    /// If a tool was called in this turn, a short 1-line summary (e.g. "tool: Edit /path/file.swift").
    /// Nil if no tool was used.
    public let toolSummary: String?

    public enum Role: String, Codable, Sendable, Equatable {
        case user
        case assistant
    }

    public init(
        role: Role,
        text: String,
        timestamp: Date,
        toolSummary: String? = nil
    ) {
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.toolSummary = toolSummary
        self.id = "\(timestamp.timeIntervalSince1970)-\(role.rawValue)-\(UUID().uuidString)"
    }
}

/// A group of consecutive messages from the same role (for visual grouping).
public struct ConversationMessageGroup: Equatable, Sendable {
    public let messages: [ConversationMessage]
    public let role: ConversationMessage.Role
    public let firstTimestamp: Date

    public init(messages: [ConversationMessage]) {
        self.messages = messages
        self.role = messages.first?.role ?? .user
        self.firstTimestamp = messages.first?.timestamp ?? Date()
    }
}

/// Boundaries between conversation days for visual date separators.
public struct ConversationDayBoundary: Equatable, Sendable {
    public let date: Date
    public let messageIndex: Int
}

extension [ConversationMessage] {
    /// Group consecutive messages by role. Empty array returns empty result.
    public func groupedByConsecutiveRole() -> [ConversationMessageGroup] {
        guard !isEmpty else { return [] }

        var groups: [ConversationMessageGroup] = []
        var current: [ConversationMessage] = [self[0]]

        for i in 1..<count {
            if self[i].role == current[0].role {
                current.append(self[i])
            } else {
                groups.append(ConversationMessageGroup(messages: current))
                current = [self[i]]
            }
        }

        groups.append(ConversationMessageGroup(messages: current))
        return groups
    }

    /// Find calendar boundaries (day changes) in the conversation.
    public func dayBoundaries() -> [ConversationDayBoundary] {
        guard !isEmpty else { return [] }

        var boundaries: [ConversationDayBoundary] = []
        let calendar = Calendar.current
        var lastDay = calendar.component(.day, from: self[0].timestamp)

        for i in 1..<count {
            let currentDay = calendar.component(.day, from: self[i].timestamp)
            if currentDay != lastDay {
                boundaries.append(ConversationDayBoundary(date: self[i].timestamp, messageIndex: i))
                lastDay = currentDay
            }
        }

        return boundaries
    }
}
