import Foundation

/// How much a permission request can cost you if it is answered wrongly.
///
/// Exists because the island can now be answered by voice, and a recogniser
/// that writes "Linkスタート" for "リンクスタート" will eventually write
/// something that reads as "はい". A misheard yes on a file read is nothing; a
/// misheard yes on a shell command is not recoverable.
///
/// Deliberately coarse. Two levels are actionable — ask again, or don't — and a
/// finer scale would only invite argument about where each tool sits.
public enum PermissionRisk: Equatable, Sendable {
    /// Reads, searches, lookups. Answering wrongly wastes a moment.
    case ordinary
    /// Writes, runs, deletes. Answering wrongly changes the machine.
    case elevated

    /// Tools that only ever look. Anything not on this list is treated as
    /// elevated — an unknown tool is exactly the case to be careful with, and a
    /// new agent's new tool should not arrive pre-trusted.
    private static let readOnlyTools: Set<String> = [
        "read", "grep", "glob", "ls", "websearch", "webfetch",
        "todowrite", "notebookread", "listmcpresources", "readmcpresource",
    ]

    public static func of(toolName: String?) -> PermissionRisk {
        guard let name = toolName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !name.isEmpty else {
            // No tool named at all. Cannot argue it is safe.
            return .elevated
        }
        // MCP tools arrive as `mcp__server__tool`; judge the last segment.
        let leaf = name.split(separator: "_").last.map(String.init) ?? name
        return readOnlyTools.contains(name) || readOnlyTools.contains(leaf) ? .ordinary : .elevated
    }
}

/// Makes a spoken "yes" say itself twice before anything irreversible happens.
///
/// The keyboard and the mouse do not need this: pressing Allow is deliberate in
/// a way that speech is not. A voice answer passes through a recogniser, and
/// the room is full of other people's sentences.
public enum VoiceApprovalGate: Sendable {
    /// A pending confirmation, waiting for the same answer a second time.
    public struct Pending: Equatable, Sendable {
        public let sessionID: String
        public let askedAt: Date

        public init(sessionID: String, askedAt: Date) {
            self.sessionID = sessionID
            self.askedAt = askedAt
        }
    }

    /// Long enough to press the key and speak again, short enough that a yes
    /// said to something else entirely cannot land here.
    public static let confirmationWindow: TimeInterval = 45

    /// True when this approval should be held back and asked again.
    public static func needsSecondSay(
        risk: PermissionRisk,
        pending: Pending?,
        sessionID: String,
        now: Date
    ) -> Bool {
        guard risk == .elevated else { return false }
        guard let pending,
              pending.sessionID == sessionID,
              now.timeIntervalSince(pending.askedAt) <= confirmationWindow
        else {
            // Nothing pending for this card, or the window has passed.
            return true
        }
        return false
    }
}
