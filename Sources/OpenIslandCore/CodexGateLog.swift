import Foundation

/// A single line from codex-findings.jsonl representing a gate result for a project.
public struct CodexGateLine: Equatable, Sendable, Decodable {
    /// ISO8601 timestamp with Z suffix
    public let ts: String?
    /// Project name
    public let project: String?
    /// Branch name
    public let branch: String?
    /// "pass", "fail", or nil if result field is present instead
    public let gate: String?
    /// Number of P1 findings (only on failures)
    public let p1_count: Int?
    /// Absolute path to detail file with P1 excerpt
    public let detail: String?
    /// "timeout" or "error" — neither pass nor fail
    public let result: String?
    /// Optional reason for result
    public let reason: String?

    enum CodingKeys: String, CodingKey {
        case ts, project, branch, gate, p1_count, detail, result, reason
    }
}

/// A Codex quality gate failure relevant to the island.
public struct CodexFailure: Equatable, Sendable {
    public let project: String
    public let branch: String
    public let p1Count: Int
    public let detailPath: String?
    public let timestamp: Date

    public init(project: String, branch: String, p1Count: Int, detailPath: String?, timestamp: Date) {
        self.project = project
        self.branch = branch
        self.p1Count = p1Count
        self.detailPath = detailPath
        self.timestamp = timestamp
    }
}

/// Parses codex-findings.jsonl to identify recent failures by project.
public enum CodexGateLog {
    /// Returns the newest gate result per project, keeping only projects with
    /// failures within the time window.
    ///
    /// - Parameters:
    ///   - lines: Individual lines from codex-findings.jsonl
    ///   - now: Reference date for window calculation
    ///   - window: Maximum age of relevant failures (default 24 hours)
    /// - Returns: Dictionary of project → failure, or empty dict if no failures
    public static func latestFailure(
        lines: [String],
        now: Date,
        window: TimeInterval = 24 * 3600
    ) -> [String: CodexFailure] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var latestPerProject: [String: (line: CodexGateLine, index: Int)] = [:]

        for (index, line) in lines.enumerated() {
            guard let data = line.data(using: .utf8),
                  let parsed = try? decoder.decode(CodexGateLine.self, from: data) else {
                // Unparsable lines are skipped
                continue
            }

            guard let project = parsed.project else { continue }

            // Keep the newest (highest index) line per project
            if (latestPerProject[project]?.index ?? -1) < index {
                latestPerProject[project] = (parsed, index)
            }
        }

        var failures: [String: CodexFailure] = [:]

        for (project, (line, _)) in latestPerProject {
            // Pass after fail clears it — skip if latest is a pass
            if line.gate == "pass" {
                continue
            }

            // Error/timeout lines are neither pass nor fail — skip
            if line.result != nil {
                continue
            }

            // Only keep failures within the window
            guard line.gate == "fail" else { continue }
            guard let project = line.project,
                  let branch = line.branch,
                  let p1Count = line.p1_count else {
                continue
            }

            // Parse timestamp
            let timestamp: Date
            if let tsString = line.ts, let parsed = ISO8601DateFormatter().date(from: tsString) {
                timestamp = parsed
            } else {
                // Fall back to now if timestamp is missing
                timestamp = now
            }

            let age = now.timeIntervalSince(timestamp)
            guard age >= 0, age <= window else {
                continue
            }

            failures[project] = CodexFailure(
                project: project,
                branch: branch,
                p1Count: p1Count,
                detailPath: line.detail,
                timestamp: timestamp
            )
        }

        return failures
    }
}
