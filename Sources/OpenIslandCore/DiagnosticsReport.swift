import Foundation

/// A plain-text snapshot of what the app can see, for attaching to a bug report.
///
/// Written as text rather than JSON because the person reading it is a human
/// deciding whether something looks wrong, not a parser.
///
/// Nothing here is uploaded anywhere. The file is written to disk and revealed
/// in Finder; sending it is the user's decision, which is why it must be
/// readable enough for them to check what they are about to send.
public struct DiagnosticsReport: Sendable {
    public struct SessionLine: Sendable {
        public let tool: String
        public let phase: String
        public let terminalApp: String?
        public let isVisible: Bool
        public let updatedSecondsAgo: Int

        public init(tool: String, phase: String, terminalApp: String?, isVisible: Bool, updatedSecondsAgo: Int) {
            self.tool = tool
            self.phase = phase
            self.terminalApp = terminalApp
            self.isVisible = isVisible
            self.updatedSecondsAgo = updatedSecondsAgo
        }
    }

    public var appVersion: String
    public var systemVersion: String
    public var installedAgents: [String]
    public var sessions: [SessionLine]
    public var activeFilterCount: Int
    public var quietScenes: [String]
    public var generatedAt: Date

    public init(
        appVersion: String,
        systemVersion: String,
        installedAgents: [String],
        sessions: [SessionLine],
        activeFilterCount: Int,
        quietScenes: [String],
        generatedAt: Date
    ) {
        self.appVersion = appVersion
        self.systemVersion = systemVersion
        self.installedAgents = installedAgents
        self.sessions = sessions
        self.activeFilterCount = activeFilterCount
        self.quietScenes = quietScenes
        self.generatedAt = generatedAt
    }

    /// Deliberately carries no working directories, prompts or session titles.
    ///
    /// Those are the fields most likely to hold a client name or a private
    /// repository path, and none of them are needed to tell whether hooks are
    /// firing. A report nobody dares send is worse than a shorter one.
    public func rendered() -> String {
        var lines = [
            "Mitama Island diagnostics",
            "generated  \(ISO8601DateFormatter().string(from: generatedAt))",
            "app        \(appVersion)",
            "macOS      \(systemVersion)",
            "",
            "agents installed (\(installedAgents.count))"
        ]
        lines += installedAgents.isEmpty ? ["  none"] : installedAgents.map { "  \($0)" }

        lines += ["", "sessions (\(sessions.count))"]
        if sessions.isEmpty {
            lines.append("  none")
        } else {
            for session in sessions {
                let host = session.terminalApp ?? "unknown host"
                let visibility = session.isVisible ? "shown" : "filtered out"
                lines.append("  \(session.tool) · \(session.phase) · \(host) · \(visibility) · \(session.updatedSecondsAgo)s ago")
            }
        }

        lines += ["", "notification filters active  \(activeFilterCount)"]
        lines.append("quiet scenes in effect       \(quietScenes.isEmpty ? "none" : quietScenes.joined(separator: ", "))")
        lines += [
            "",
            "No working directories, prompts or session titles are included.",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    /// Writes the report and returns where it landed.
    @discardableResult
    public func write(to directory: URL, fileManager: FileManager = .default) throws -> URL {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        // Seconds in the name: two reports a minute apart must not overwrite
        // each other, which is exactly what happens while chasing one bug.
        let stamp = Int(generatedAt.timeIntervalSince1970)
        let url = directory.appending(path: "mitama-island-diagnostics-\(stamp).txt")
        try rendered().write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
