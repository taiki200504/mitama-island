import OpenIslandCore
import SwiftUI

/// The rest of mitama, in at most three lines above the session list: the
/// browser being driven, what the job queue is doing, and a failing Codex
/// gate. Each line is drawn only when its signal is there, so a quiet
/// machine leaves the panel exactly as it was.
struct IslandEcosystemSignalsStrip: View {
    @Bindable var model: AppModel
    var sideInset: CGFloat

    /// The Codex excerpt is read from disk only after the row is tapped —
    /// the island never holds a review it hasn't been asked for.
    @State private var codexExcerpt: String?
    @State private var showsCodexExcerpt = false

    private var lang: LanguageManager { model.lang }

    private var automation: BrowserAutomationActivity? {
        guard model.automationSignalEnabled, model.ecosystemSignals.state.automationIsRunning else {
            return nil
        }
        return model.ecosystemSignals.state.automationActivity
    }

    private var automationIsRunning: Bool {
        model.automationSignalEnabled && model.ecosystemSignals.state.automationIsRunning
    }

    private var jobSummary: MitamaJobSummary? {
        guard model.jobSignalEnabled else { return nil }
        return model.mitamaFeed.jobSummary
    }

    private var codexFailure: CodexFailure? {
        guard model.codexSignalEnabled else { return nil }
        return model.ecosystemSignals.state.codexFailure
    }

    var body: some View {
        if automationIsRunning || jobSummary != nil || codexFailure != nil {
            VStack(alignment: .leading, spacing: 3) {
                if automationIsRunning {
                    line(
                        icon: "bolt.horizontal.circle",
                        tint: SAOGrammar.Palette.systemCyan,
                        text: automationText
                    )
                }

                if let jobSummary {
                    line(
                        icon: "square.stack.3d.up",
                        tint: V6Palette.paper.opacity(0.7),
                        text: jobText(jobSummary)
                    )
                }

                if let codexFailure {
                    Button {
                        toggleCodexExcerpt(codexFailure)
                    } label: {
                        line(
                            icon: "exclamationmark.triangle",
                            tint: SAOGrammar.Palette.danger,
                            text: codexText(codexFailure)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(lang.t("island.signal.codex.hint"))

                    if showsCodexExcerpt {
                        Text(codexExcerpt ?? lang.t("island.signal.codex.noDetail"))
                            .font(.islandMono(size: 10))
                            .foregroundStyle(V6Palette.paper.opacity(0.68))
                            .lineLimit(8)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 16)
                    }
                }
            }
            .padding(.horizontal, sideInset)
            .padding(.bottom, 4)
        }
    }

    private func line(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.islandMono(size: 10.5))
                .foregroundStyle(V6Palette.paper.opacity(0.82))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }

    private var automationText: String {
        guard let automation else { return lang.t("island.signal.automation") }
        // The page the browser was last sent to, host-only when it has no
        // title yet — a bare URL path reads as noise at this size.
        let where_ = automation.title.isEmpty
            ? (automation.url?.host() ?? "")
            : automation.title
        let parts = [lang.t("island.signal.automation"), automation.accountLabel, where_]
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func jobText(_ summary: MitamaJobSummary) -> String {
        String(
            format: lang.t("island.signal.jobs"),
            summary.runningCount,
            summary.enqueuedCount,
            summary.completedTodayCount
        )
    }

    private func codexText(_ failure: CodexFailure) -> String {
        String(
            format: lang.t("island.signal.codex"),
            failure.project,
            failure.branch,
            failure.p1Count
        )
    }

    private func toggleCodexExcerpt(_ failure: CodexFailure) {
        showsCodexExcerpt.toggle()
        guard showsCodexExcerpt, codexExcerpt == nil, let path = failure.detailPath else { return }
        codexExcerpt = EcosystemSignalsCoordinator.codexExcerpt(at: path)
    }
}
