import Foundation
import Observation
import os
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
    private static let logger = Logger(subsystem: "com.mitama.island", category: "mitama")

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

    /// The job queue's own numbers, refreshed on the same loop as the feed —
    /// a second timer would double the traffic for the same answer.
    private(set) var jobSummary: MitamaJobSummary?

    /// 返事待ちの RSI 提案。古いものから最大3件。
    ///
    /// 7日放っておくと RSI が毎朝 urgent で催促する。その催促を島で止められる
    /// 唯一の口なので、通知を読むのと同じ周回で拾う。
    private(set) var proposals: [MitamaProposal] = []

    /// ハーネス用。ジョブの数え上げはデータベース越しなので、撮るときは
    /// ここに置いた値をそのまま出す。
    func loadJobSummaryFixture(_ summary: MitamaJobSummary?) {
        jobSummary = summary
    }

    /// ハーネス用。提案も同じ理由でデータベース越し。
    func loadProposalsFixture(_ proposals: [MitamaProposal]) {
        self.proposals = proposals
    }

    /// 放置画面に出す脈と今日の1枚。60秒の周回には乗せない——盤面は1時間ごと
    /// にしか変わらず、カードは1日1枚で足りるので、毎分引いても同じ答えが返る。
    private(set) var pulse: MitamaPulse?
    private(set) var learnCard: MitamaLearnCard?

    /// ハーネス用。
    func loadAmbientFixture(pulse: MitamaPulse?, card: MitamaLearnCard?) {
        self.pulse = pulse
        self.learnCard = card
    }
    /// Off until the owner turns the signal on, so a disabled signal costs
    /// no query at all.
    @ObservationIgnored var jobSummaryEnabled = false
    /// Called once per job that finished since the previous poll. The first
    /// poll never fires — see `MitamaJobCompletionDetector`.
    @ObservationIgnored var onJobCompleted: ((MitamaJobCompletion) -> Void)?
    @ObservationIgnored private var lastJobPollAt: Date?

    @ObservationIgnored private var client: MitamaNotificationClient?
    @ObservationIgnored private(set) var workLog: MitamaWorkLogClient?
    @ObservationIgnored private var proposalClient: MitamaProposalClient?
    @ObservationIgnored private var ambientClient: MitamaAmbientClient?
    @ObservationIgnored private var ambientFetchedAt: Date?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var currentInterval = MitamaFeedCoordinator.pollInterval
    /// Set by `AppModel` when the Watch endpoint is running. Nil is the normal
    /// case — most people never pair a watch.
    @ObservationIgnored var watchRelay: WatchNotificationRelay?

    var isRunning: Bool { pollTask != nil }

    /// Starts polling once credentials are in hand.
    ///
    /// The credentials are fetched off the main actor, and that is not a
    /// nicety. `SecItemCopyMatching` blocks for as long as macOS takes to decide
    /// whether to show its "wants to use a keychain item" prompt, and this is
    /// called from `AppModel.init` — inside SwiftUI's scene construction. Read
    /// on the main actor, the prompt cannot be drawn until the app finishes
    /// launching and the app cannot finish launching until the prompt is
    /// answered. The whole app hung at a black screen with no window and no log.
    func start(environmentFileURL: URL = MitamaEnvironment.defaultEnvFileURL) {
        guard pollTask == nil else { return }

        pollTask = Task { [weak self] in
            let loaded = await Task.detached(priority: .utility) {
                MitamaEnvironment.loadWithSource(from: environmentFileURL)
            }.value

            // The keychain read can outlive a `stop()`, and assigning a client
            // after that would leave a stopped feed holding live credentials.
            guard let self, !Task.isCancelled else { return }
            guard let loaded else {
                Self.logger.notice("No credentials in the keychain or the .env file")
                self.isConfigured = false
                self.credentialSource = nil
                self.pollTask = nil
                return
            }

            self.isConfigured = true
            self.credentialSource = loaded.source
            // Which source won is the one thing worth knowing when the feed
            // misbehaves, and it is also how you check that reading the
            // keychain no longer puts a password panel on screen.
            Self.logger.notice("Credentials from \(String(describing: loaded.source), privacy: .public)")
            self.client = MitamaNotificationClient(environment: loaded.environment)
            self.workLog = MitamaWorkLogClient(environment: loaded.environment)
            self.proposalClient = MitamaProposalClient(environment: loaded.environment)
            self.ambientClient = MitamaAmbientClient(environment: loaded.environment)
            self.currentInterval = Self.pollInterval

            while !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(for: .seconds(self.currentInterval))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        workLog = nil
        proposalClient = nil
        ambientClient = nil
        ambientFetchedAt = nil
        notifications = []
        proposals = []
        pulse = nil
        learnCard = nil
        jobSummary = nil
        lastJobPollAt = nil
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
            await refreshJobSummary()
            if let proposalClient {
                proposals = await proposalClient.openProposals()
            }
        } catch {
            // Back off instead of hammering: the usual failure here is being
            // offline, and that can last hours.
            currentInterval = min(currentInterval * 2, Self.maxPollInterval)
        }
    }

    /// The queue's counts, plus a sneak peek for each job that finished since
    /// the previous poll.
    private func refreshJobSummary() async {
        guard jobSummaryEnabled, let workLog else {
            jobSummary = nil
            return
        }
        guard let summary = await workLog.jobSummary() else { return }
        jobSummary = summary

        let completions: [MitamaJobCompletion]
        if let objective = summary.lastCompletedObjective, let at = summary.lastCompletedAt {
            completions = [MitamaJobCompletion(objective: objective, completedAt: at)]
        } else {
            completions = []
        }
        for completion in MitamaJobCompletionDetector.detectNew(current: completions, since: lastJobPollAt) {
            onJobCompleted?(completion)
        }
        lastJobPollAt = .now
    }

    /// 提案に「やる／捨てる」を返す。
    ///
    /// 行は押した瞬間に手元から消す。送りが通ったかは次の周回で分かるし、通らな
    /// ければ提案はそのまま返事待ちのまま出てくる——消えたのに催促が続くより、
    /// 一度消えてまた出てくる方が読み違えようがない。
    func reply(to proposal: MitamaProposal, _ reply: MitamaProposalReply) {
        proposals.removeAll { $0.id == proposal.id }
        guard let workLog else { return }
        Task {
            await workLog.perform(.replyToProposal(runDate: proposal.runDate, reply: reply))
        }
    }

    /// 放置画面を出す直前に呼ぶ。待たない——この提示は今ある値で描き、取り直した
    /// 分は次の提示に効く（放置画面の動画一覧と同じ作法）。
    func refreshAmbient(now: Date = .now) {
        guard let ambientClient else { return }
        if let ambientFetchedAt, now.timeIntervalSince(ambientFetchedAt) < MitamaAmbientClient.freshness {
            return
        }
        ambientFetchedAt = now

        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: now)?.start
            ?? Calendar.current.startOfDay(for: now)
        Task { [weak self] in
            let fetched = await ambientClient.fetch(weekStart: weekStart, now: now)
            guard let self, !Task.isCancelled else { return }
            self.pulse = fetched.pulse
            self.learnCard = fetched.card
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
