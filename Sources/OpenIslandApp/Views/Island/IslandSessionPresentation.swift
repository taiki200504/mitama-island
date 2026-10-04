import SwiftUI
import OpenIslandCore

/// Phase headings stay visible even when sessions are grouped by workspace or provider.
enum IslandSessionPriority: CaseIterable, Identifiable {
    case attention, running, completed
    var id: Self { self }
    func contains(_ session: AgentSession) -> Bool {
        switch self {
        case .attention: session.phase.requiresAttention
        case .running: session.phase == .running
        case .completed: session.phase == .completed
        }
    }
    @MainActor var title: String {
        let key = switch self {
        case .attention: "island.priority.attention"
        case .running: "island.priority.running"
        case .completed: "island.priority.completed"
        }
        return LanguageManager.shared.t(key)
    }
}

/// The same conversation identity appears above list details and decision cards.
struct IslandSessionContextView: View {
    let session: AgentSession
    let title: String
    var modeLabel: String?
    var showsWorkspace = true
    var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.islandDecision(size: 14, weight: .semibold))
                .foregroundStyle(V6Palette.paper)
                .lineLimit(expanded ? 2 : 1)
                .help(title)
            if showsWorkspace, !session.spotlightWorkspaceName.isEmpty {
                Text(session.spotlightWorkspaceName)
                    .font(.islandDecision(size: 12))
                    .foregroundStyle(V6Palette.paper.opacity(0.78))
                    .lineLimit(1)
                    .help(session.spotlightWorkspaceName)
            }
            Text([session.jumpTarget?.terminalApp, session.tool.displayName, modeLabel]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.islandDecision(size: 12))
                .foregroundStyle(V6Palette.paper.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func islandDecisionCard() -> some View {
        self.padding(12)
            .background(IslandThemes.current.ink, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(V6Palette.paper.opacity(0.14)))
    }
}

extension Font {
    /// Decision text stays readable at small settings and follows larger saved text sizes.
    @MainActor static func islandDecision(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: max(size, IslandTypography.scaled(size)), weight: weight, design: design)
    }
}
