import Foundation

/// Summary of mitama job queue state.
public struct MitamaJobSummary: Equatable, Sendable {
    /// Number of jobs currently running
    public let runningCount: Int
    /// Number of jobs waiting in the queue
    public let enqueuedCount: Int
    /// Number of jobs completed since local midnight
    public let completedTodayCount: Int
    /// Objective of the most recently completed job
    public let lastCompletedObjective: String?
    /// Timestamp of the most recently completed job
    public let lastCompletedAt: Date?

    public init(
        runningCount: Int,
        enqueuedCount: Int,
        completedTodayCount: Int,
        lastCompletedObjective: String?,
        lastCompletedAt: Date?
    ) {
        self.runningCount = runningCount
        self.enqueuedCount = enqueuedCount
        self.completedTodayCount = completedTodayCount
        self.lastCompletedObjective = lastCompletedObjective
        self.lastCompletedAt = lastCompletedAt
    }
}

/// One finished session, as mitama counts it.
///
/// mitama's scoreboard measures how much its owner actually built, and the
/// island is the only thing that sees every agent session start and stop. What
/// it sends is deliberately thin: which agent, when, how long. Not the prompt,
/// not the directory, not the tools — the count is the point, and the contents
/// of someone's work are not mitama's to hold.
public struct IslandSessionRecord: Equatable, Sendable {
    public enum Status: String, Sendable {
        case completed
        case cancelled
    }

    public let sessionID: String
    public let agentID: String
    public let startedAt: Date
    public let endedAt: Date
    public let status: Status

    public init(sessionID: String, agentID: String, startedAt: Date, endedAt: Date, status: Status) {
        self.sessionID = sessionID
        self.agentID = agentID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
    }

    public var durationSeconds: Int {
        max(0, Int(endedAt.timeIntervalSince(startedAt)))
    }

    /// Keyed on the session so a replay after a restart lands on the same row
    /// rather than counting the same afternoon twice.
    var rowID: String { "\(sessionID):\(status.rawValue)" }

    func body(formatter: ISO8601DateFormatter) -> [String: Any] {
        [
            "id": rowID,
            "agent_id": agentID,
            "session_id": sessionID,
            "started_at": formatter.string(from: startedAt),
            "ended_at": formatter.string(from: endedAt),
            "duration_seconds": durationSeconds,
            "status": status.rawValue,
        ]
    }
}

/// One of mitama's agents, as the island offers it.
public struct MitamaAgent: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// A piece of work handed to mitama from the island.
public struct IslandJobSubmission: Equatable, Sendable {
    public let objective: String
    public let agentID: String

    public init(objective: String, agentID: String) {
        self.objective = objective
        self.agentID = agentID
    }
}

/// Writes the island's side of the mitama ledger: what got worked on, and what
/// the user handed over.
///
/// Every call fails silently. The island's job is watching local agents, and it
/// has to keep doing that on a plane, behind a captive portal, or with the key
/// not yet configured — none of which are the user's problem to hear about.
public struct MitamaWorkLogClient: Sendable {
    private let environment: MitamaEnvironment
    private let session: URLSession

    public init(environment: MitamaEnvironment, session: URLSession = .shared) {
        self.environment = environment
        self.session = session
    }

    /// True when the row reached mitama. Callers use it for the settings screen's
    /// "did that work" feedback; the telemetry path ignores it.
    @discardableResult
    public func record(_ record: IslandSessionRecord) async -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return await post(
            table: "mos_island_sessions",
            body: record.body(formatter: formatter),
            // A session the island already reported is not an error worth
            // retrying — the replay is the expected case, not the exception.
            preferences: "resolution=ignore-duplicates"
        )
    }

    @discardableResult
    public func enqueue(_ job: IslandJobSubmission) async -> Bool {
        await post(
            table: "mos_job_queue",
            body: [
                "id": UUID().uuidString,
                "agent_id": job.agentID,
                "source": "island",
                "status": "enqueued",
                "input": ["objective": job.objective],
            ]
        )
    }

    /// The agents mitama will actually run work for, newest first.
    ///
    /// Derived from jobs that completed rather than from a roster table: the
    /// roster lives in mitama's skill files, not in the database, and the
    /// orchestrator refuses work for an agent it does not know. A job that
    /// finished is the only proof from here that an agent exists and runs.
    public func activeAgents(since: Date) async -> [MitamaAgent] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        guard let url = environment.endpoint(
            "mos_job_queue",
            queryItems: [
                URLQueryItem(name: "select", value: "agent_id"),
                URLQueryItem(name: "status", value: "eq.completed"),
                URLQueryItem(name: "created_at", value: "gte.\(formatter.string(from: since))"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "500"),
            ]
        ) else { return [] }

        guard let (data, response) = try? await session.data(for: environment.authorized(URLRequest(url: url))),
              let status = (response as? HTTPURLResponse)?.statusCode,
              (200..<300).contains(status),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        var seen: Set<String> = []
        return rows.compactMap { $0["agent_id"] as? String }
            .filter { seen.insert($0).inserted }
            .map { MitamaAgent(id: $0, name: $0) }
    }

    /// Sessions and hours logged since `since`.
    ///
    /// Read back rather than counted locally, so the island shows the number
    /// mitama's scoreboard will show. A count that only matches on the machine
    /// that produced it is not a shared measure of anything.
    public func weekSoFar(since: Date) async -> (sessions: Int, seconds: Int)? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        guard let url = environment.endpoint(
            "mos_island_sessions",
            queryItems: [
                URLQueryItem(name: "select", value: "duration_seconds"),
                URLQueryItem(name: "recorded_at", value: "gte.\(formatter.string(from: since))"),
            ]
        ) else { return nil }

        guard let (data, response) = try? await session.data(for: environment.authorized(URLRequest(url: url))),
              let status = (response as? HTTPURLResponse)?.statusCode,
              (200..<300).contains(status),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        return (rows.count, rows.reduce(0) { $0 + (($1["duration_seconds"] as? Int) ?? 0) })
    }

    /// Fetches current job queue state: running, enqueued, completed today,
    /// and details of the most recent completion.
    ///
    /// Returns `nil` if the query fails or authorization is not available.
    /// The island keeps drawing if this returns `nil`.
    public func jobSummary() async -> MitamaJobSummary? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let now = Date()
        let todayStart = Calendar.current.startOfDay(for: now)

        // Query running jobs
        guard let runningCount = await queryStatusCount(status: "running") else { return nil }

        // Query enqueued jobs
        guard let enqueuedCount = await queryStatusCount(status: "enqueued") else { return nil }

        // Query completed jobs today
        guard let completedToday = await queryCompletedSince(date: todayStart) else { return nil }

        return MitamaJobSummary(
            runningCount: runningCount,
            enqueuedCount: enqueuedCount,
            completedTodayCount: completedToday.count,
            lastCompletedObjective: completedToday.first?.objective,
            lastCompletedAt: completedToday.first?.completedAt
        )
    }

    private func queryStatusCount(status: String) async -> Int? {
        guard let url = environment.endpoint(
            "mos_job_queue",
            queryItems: [
                URLQueryItem(name: "select", value: "count"),
                URLQueryItem(name: "status", value: "eq.\(status)"),
            ]
        ) else { return nil }

        guard let (data, response) = try? await session.data(for: environment.authorized(URLRequest(url: url))),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            return nil
        }

        // Supabase returns count via Content-Range header or in the response
        if let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range"),
           let match = contentRange.range(of: "/(\\d+)", options: .regularExpression) {
            let numberStr = String(contentRange[match]).dropFirst().dropLast()
            return Int(numberStr)
        }

        // Fallback: count array length from JSON response
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return arr.count
        }

        return nil
    }

    private func queryCompletedSince(date: Date) async -> [(objective: String, completedAt: Date)]? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        guard let url = environment.endpoint(
            "mos_job_queue",
            queryItems: [
                URLQueryItem(name: "select", value: "input,completed_at"),
                URLQueryItem(name: "status", value: "eq.completed"),
                URLQueryItem(name: "completed_at", value: "gte.\(formatter.string(from: date))"),
                URLQueryItem(name: "order", value: "completed_at.desc"),
                URLQueryItem(name: "limit", value: "100"),
            ]
        ) else { return nil }

        guard let (data, response) = try? await session.data(for: environment.authorized(URLRequest(url: url))),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        var results: [(objective: String, completedAt: Date)] = []
        for row in rows {
            var objective = "Unknown"
            if let input = row["input"] as? [String: Any],
               let obj = input["objective"] as? String {
                objective = obj
            } else if let input = row["input"] as? String {
                // input might be a JSON string
                if let inputData = input.data(using: .utf8),
                   let inputObj = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any],
                   let obj = inputObj["objective"] as? String {
                    objective = obj
                }
            }

            var completedAt = Date()
            if let completedAtStr = row["completed_at"] as? String,
               let parsed = formatter.date(from: completedAtStr) {
                completedAt = parsed
            }

            results.append((objective, completedAt))
        }

        return results
    }

    private func post(table: String, body: [String: Any], preferences: String? = nil) async -> Bool {
        guard let url = environment.endpoint(table),
              let payload = try? JSONSerialization.data(withJSONObject: [body]) else {
            return false
        }

        var request = environment.authorized(URLRequest(url: url))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let preferences {
            request.setValue(preferences, forHTTPHeaderField: "Prefer")
        }
        request.httpBody = payload

        guard let (_, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else {
            return false
        }
        return (200..<300).contains(status)
    }
}
