import Foundation
import os

/// HTTP is injected so the relay's decisions (what to apply, what to drop) can
/// be tested without a network. `URLSession` is the production implementation.
public protocol MitamaRemoteHTTP: Sendable {
    func perform(_ request: URLRequest) async throws -> (data: Data, status: Int)
}

extension URLSession: MitamaRemoteHTTP {
    public func perform(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        let (data, response) = try await data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? -1)
    }
}

/// Mirrors the island's permission / question prompts to mitama
/// (`mos_island_requests` + an urgent `mos_notifications` row) so they can be
/// answered from the iPhone, and applies the answer back through the same
/// callbacks `WatchNotificationRelay` uses.
///
/// The Mac stays the source of truth: nothing here is required for the island
/// to be answered locally, so every failure is logged and swallowed.
public final class MitamaRemoteRelay: @unchecked Sendable {
    private static let logger = Logger(subsystem: "app.openisland", category: "MitamaRemoteRelay")

    public static let pollInterval: TimeInterval = 3
    /// Matches the table's `expires_at` default.
    public static let requestLifetime: TimeInterval = 30 * 60
    static let summaryHead = 350
    static let summaryTail = 150

    /// requestID is passed so the app can refuse an answer meant for a prompt that is no longer the current one.
    public var onResolvePermission: (@Sendable (_ sessionID: String, _ requestID: String, _ approved: Bool) -> Void)?
    public var onAnswerQuestion: (@Sendable (_ sessionID: String, _ requestID: String, _ answer: String) -> Void)?

    enum Kind: String, Sendable { case permission, question }

    struct Pending: Sendable {
        let sessionID: String
        let kind: Kind
        let options: [String]
        let createdAt: Date
    }

    private let http: MitamaRemoteHTTP
    private let environmentLoader: @Sendable () -> MitamaEnvironment?
    private let now: @Sendable () -> Date
    private let autoPoll: Bool

    private let lock = NSLock()
    /// Off until the app turns it on: a model built in tests must never write to the real mitama.
    private var enabled = false
    private var pending: [String: Pending] = [:]
    private var environment: MitamaEnvironment?
    private var pollTask: Task<Void, Never>?

    public init(
        http: MitamaRemoteHTTP = URLSession.shared,
        environmentLoader: @escaping @Sendable () -> MitamaEnvironment? = { MitamaEnvironment.load() },
        now: @escaping @Sendable () -> Date = { Date() },
        autoPoll: Bool = true
    ) {
        self.http = http
        self.environmentLoader = environmentLoader
        self.now = now
        self.autoPoll = autoPoll
    }

    /// Off means nothing is sent and nothing is polled. Turning it off also
    /// forgets local pending requests, so a later answer cannot be applied.
    public var isEnabled: Bool {
        get { locked { enabled } }
        set {
            locked {
                enabled = newValue
                if !newValue {
                    pending.removeAll()
                    pollTask?.cancel()
                    pollTask = nil
                }
            }
        }
    }

    // MARK: - Event Notification

    /// Called by AppModel after applying a tracked event, next to `WatchNotificationRelay`.
    public func notifyEvent(_ event: AgentEvent, session: AgentSession?) {
        guard isEnabled else { return }
        Task.detached { [self] in await handle(event, session: session) }
    }

    func handle(_ event: AgentEvent, session: AgentSession?) async {
        switch event {
        case let .permissionRequested(payload):
            let request = payload.request
            await register(
                id: request.id.uuidString,
                sessionID: payload.sessionID,
                kind: .permission,
                agentTool: session?.tool.displayName ?? "Agent",
                title: request.title,
                summary: request.summary,
                options: [],
                primaryAction: request.primaryActionTitle,
                secondaryAction: request.secondaryActionTitle
            )

        case let .questionAsked(payload):
            let prompt = payload.prompt
            // Without options there is nothing to tap on the phone.
            guard !prompt.options.isEmpty else { return }
            await register(
                id: prompt.id.uuidString,
                sessionID: payload.sessionID,
                kind: .question,
                agentTool: session?.tool.displayName ?? "Agent",
                title: prompt.title,
                summary: "",
                options: prompt.options,
                primaryAction: nil,
                secondaryAction: nil
            )

        case let .actionableStateResolved(payload):
            await resolveElsewhere(sessionID: payload.sessionID)

        default:
            break
        }
    }

    // MARK: - Register

    func register(
        id: String,
        sessionID: String,
        kind: Kind,
        agentTool: String,
        title: String,
        summary: String,
        options: [String],
        primaryAction: String?,
        secondaryAction: String?
    ) async {
        guard isEnabled, let env = await resolvedEnvironment() else { return }

        // Tracked before the insert returns: a Mac-side answer can arrive while the request is in flight.
        let created = now()
        locked { pending[id] = Pending(sessionID: sessionID, kind: kind, options: options, createdAt: created) }

        var row: [String: Any] = [
            "id": id,
            "session_id": sessionID,
            "kind": kind.rawValue,
            "agent_tool": agentTool,
            "title": Self.redact(title).prefix(120).description,
            "summary": Self.makeSummary(summary),
            "options": options,
        ]
        if let primaryAction { row["primary_action"] = primaryAction }
        if let secondaryAction { row["secondary_action"] = secondaryAction }

        let inserted = await send(env, table: "mos_island_requests", method: "POST", body: row,
                                  prefer: "resolution=ignore-duplicates")
        guard inserted != nil else {
            locked { _ = pending.removeValue(forKey: id) }
            return
        }

        _ = await send(env, table: "mos_notifications", method: "POST", body: [
            "level": "urgent",
            "title": "\(agentTool): 確認待ち",
            "body": Self.redact(title).prefix(100).description,
            "read": false,
            "source_ref": "island:\(id)",
        ])

        startPollingIfNeeded()
    }

    // MARK: - Poll

    private func startPollingIfNeeded() {
        guard autoPoll else { return }
        locked {
            guard pollTask == nil, !pending.isEmpty else { return }
            pollTask = Task.detached { [self] in
                // Polls only while something is waiting; an idle island makes no requests.
                while true {
                    while !Task.isCancelled, hasPending {
                        try? await Task.sleep(for: .seconds(Self.pollInterval))
                        await pollOnce()
                    }
                    // Re-checked under the lock so a request registered just now is not stranded.
                    let done = locked { () -> Bool in
                        guard Task.isCancelled || pending.isEmpty else { return false }
                        pollTask = nil
                        return true
                    }
                    if done { return }
                }
            }
        }
    }

    private var hasPending: Bool { locked { !pending.isEmpty } }

    func pendingCountForTests() -> Int { locked { pending.count } }

    func pollOnce() async {
        guard isEnabled, hasPending, let env = await resolvedEnvironment() else { return }

        let cutoff = now().addingTimeInterval(-Self.requestLifetime)
        let expired = locked { pending.filter { $0.value.createdAt < cutoff }.map(\.key) }
        if !expired.isEmpty {
            locked { expired.forEach { pending.removeValue(forKey: $0) } }
            _ = await patch(env, filters: ["id": "in.(\(expired.joined(separator: ",")))", "status": "eq.pending"],
                            body: ["status": "expired"])
        }

        let ids = locked { Array(pending.keys) }
        guard !ids.isEmpty,
              let data = await send(env, table: "mos_island_requests", method: "GET", query: [
                  URLQueryItem(name: "select", value: "id,answer"),
                  URLQueryItem(name: "id", value: "in.(\(ids.joined(separator: ",")))"),
                  URLQueryItem(name: "status", value: "eq.answered"),
              ]),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

        for row in rows {
            guard let id = row["id"] as? String, let answer = row["answer"] as? String,
                  let entry = locked({ pending[id] }) else { continue }

            guard Self.isValid(answer: answer, for: entry) else {
                Self.logger.notice("Dropped an answer that is not one of the offered options")
                locked { _ = pending.removeValue(forKey: id) }
                _ = await patch(env, filters: ["id": "eq.\(id)", "status": "eq.answered"], body: ["status": "expired"])
                continue
            }

            // The PATCH is the lock: only the caller that moves answered -> applied
            // gets a row back, so a second island (or a replay) cannot apply it twice.
            let formatter = ISO8601DateFormatter()
            let claimed = await patch(
                env,
                filters: ["id": "eq.\(id)", "status": "eq.answered"],
                body: ["status": "applied", "applied_at": formatter.string(from: now())]
            )
            guard claimed == 1 else { continue }

            locked { _ = pending.removeValue(forKey: id) }
            switch entry.kind {
            case .permission: onResolvePermission?(entry.sessionID, id, answer == "allow")
            case .question: onAnswerQuestion?(entry.sessionID, id, answer)
            }
        }
    }

    // MARK: - Resolved on the Mac

    func resolveElsewhere(sessionID: String) async {
        let ids = locked {
            let ids = pending.filter { $0.value.sessionID == sessionID }.map(\.key)
            ids.forEach { pending.removeValue(forKey: $0) }
            return ids
        }
        guard !ids.isEmpty, let env = await resolvedEnvironment() else { return }
        _ = await patch(env, filters: ["id": "in.(\(ids.joined(separator: ",")))", "status": "in.(pending,answered)"],
                        body: ["status": "resolved_elsewhere"])
    }

    // MARK: - Pure helpers

    static func isValid(answer: String, for entry: Pending) -> Bool {
        switch entry.kind {
        case .permission: answer == "allow" || answer == "deny"
        case .question: entry.options.contains(answer)
        }
    }

    private static let secretPattern = try? NSRegularExpression(
        pattern: #"(api[_-]?key|token|secret|password|bearer)\S*\s*[:=]?\s*\S+"#,
        options: [.caseInsensitive]
    )

    static func redact(_ text: String) -> String {
        guard let secretPattern else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return secretPattern.stringByReplacingMatches(in: text, range: range, withTemplate: "***")
    }

    /// Head 350 + "…" + tail 150, so a dangerous command's end is not hidden behind a cut.
    /// Secrets are masked first so a cut cannot split one in half and leak the rest.
    static func makeSummary(_ text: String) -> String {
        let redacted = redact(text)
        guard redacted.count > summaryHead + summaryTail else { return redacted }
        return String(redacted.prefix(summaryHead)) + "…" + String(redacted.suffix(summaryTail))
    }

    // MARK: - HTTP

    private func resolvedEnvironment() async -> MitamaEnvironment? {
        if let cached = locked({ environment }) { return cached }
        // Keychain reads can block on a system prompt, so never on the caller's thread.
        let loader = environmentLoader
        let loaded = await Task.detached(priority: .utility) { loader() }.value
        locked { environment = loaded }
        return loaded
    }

    /// Returns the number of rows the PATCH changed, or nil on failure.
    private func patch(_ env: MitamaEnvironment, filters: [String: String], body: [String: Any]) async -> Int? {
        let query = filters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let data = await send(env, table: "mos_island_requests", method: "PATCH", query: query,
                                    body: body, prefer: "return=representation"),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return nil }
        return rows.count
    }

    private func send(
        _ env: MitamaEnvironment,
        table: String,
        method: String,
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil,
        prefer: String? = nil
    ) async -> Data? {
        guard let url = env.endpoint(table, queryItems: query) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }

        do {
            let (data, status) = try await http.perform(env.authorized(request))
            guard (200..<300).contains(status) else {
                Self.logger.notice("\(table, privacy: .public) \(method, privacy: .public) failed (HTTP \(status))")
                return nil
            }
            return data
        } catch {
            Self.logger.notice("\(table, privacy: .public) \(method, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
