import Foundation
import Observation
import OpenIslandCore

/// Keeps mitama's actionable notifications on the island.
///
/// The island already answers "what are my agents doing"; mitama's queue is the
/// other half of the same question — "what is waiting on me". Polling rather
/// than a socket because the queue is low-frequency and a REST read costs
/// nothing next to keeping a realtime connection alive on battery.
@MainActor
@Observable
final class MitamaFeedCoordinator {
    /// Rows shown at once. The queue routinely holds hundreds of unread
    /// homework items; an island that lists them all is a wall, not a signal.
    static let displayLimit = 4
    /// Homework older than this is backlog, not a prompt — it stays in the Hub.
    static let homeworkFreshness: TimeInterval = 24 * 60 * 60

    static let hubURL = URL(string: "https://mitama-os-hub.vercel.app/notifications")!

    private static let pollInterval: TimeInterval = 60
    private static let maxPollInterval: TimeInterval = 10 * 60

    private(set) var notifications: [MitamaNotification] = []
    private(set) var isConfigured = false
    private(set) var credentialSource: MitamaEnvironment.Source?

    @ObservationIgnored private var client: MitamaNotificationClient?
    @ObservationIgnored private(set) var workLog: MitamaWorkLogClient?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var currentInterval = MitamaFeedCoordinator.pollInterval
    /// Set by `AppModel` when the Watch endpoint is running. Nil is the normal
    /// case — most people never pair a watch.
    @ObservationIgnored var watchRelay: WatchNotificationRelay?

    var isRunning: Bool { pollTask != nil }

    func start(environmentFileURL: URL = MitamaEnvironment.defaultEnvFileURL) {
        guard pollTask == nil else { return }
        guard let loaded = MitamaEnvironment.loadWithSource(from: environmentFileURL) else {
            isConfigured = false
            credentialSource = nil
            return
        }

        isConfigured = true
        credentialSource = loaded.source
        client = MitamaNotificationClient(environment: loaded.environment)
        workLog = MitamaWorkLogClient(environment: loaded.environment)
        currentInterval = Self.pollInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let interval = self?.currentInterval else { return }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        workLog = nil
        notifications = []
    }

    /// Counts a finished session towards mitama's measure of how much its owner
    /// built this week. Silent either way — this is bookkeeping, and the island
    /// has a session list to keep drawing.
    func record(_ session: AgentSession, endedAt: Date = .now) {
        guard let workLog else { return }
        let record = IslandSessionRecord(
            sessionID: session.id,
            agentID: session.tool.rawValue,
            startedAt: session.firstSeenAt,
            endedAt: endedAt,
            status: .completed
        )
        Task { await workLog.record(record) }
    }

    func refresh() async {
        guard let client else { return }

        do {
            let rows = try await client.fetchActionable()
            notifications = Self.presentable(rows, now: .now)
            for alert in notifications where alert.level == .urgent {
                watchRelay?.notifyMitamaAlert(alert)
            }
            currentInterval = Self.pollInterval
        } catch {
            // Back off instead of hammering: the usual failure here is being
            // offline, and that can last hours.
            currentInterval = min(currentInterval * 2, Self.maxPollInterval)
        }
    }

    func markRead(_ notification: MitamaNotification) {
        notifications.removeAll { $0.id == notification.id }
        guard let client else { return }
        Task {
            try? await client.markRead(id: notification.id)
        }
    }

    /// Urgent items always surface; homework only while it is still today's.
    static func presentable(_ rows: [MitamaNotification], now: Date) -> [MitamaNotification] {
        rows
            .filter { row in
                switch row.level {
                case .urgent:
                    return true
                case .homework:
                    return now.timeIntervalSince(row.createdAt) < homeworkFreshness
                case .digest, .info:
                    return false
                }
            }
            .sorted { lhs, rhs in
                if lhs.level != rhs.level {
                    return lhs.level == .urgent
                }
                return lhs.createdAt > rhs.createdAt
            }
            .prefix(displayLimit)
            .map { $0 }
    }
}
