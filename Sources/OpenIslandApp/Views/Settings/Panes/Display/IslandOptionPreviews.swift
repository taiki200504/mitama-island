import OpenIslandCore
import SwiftUI

struct CountBadgePreview: View {
    let count: Int
    var body: some View {
        Text("×\(count)")
            .font(.islandMono(size: 12, weight: .semibold))
            .foregroundStyle(V6Palette.paper.opacity(0.72))
    }
}

struct AgentsMiniGridPreview: View {
    var body: some View {
        let claude = Color(hex: AgentTool.claudeCode.brandColorHex) ?? V6Palette.paper
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in
                IslandThemes.current.shape(cornerRadius: 1.5)
                    .fill(claude)
                    .frame(width: 8, height: 8)
            }
        }
    }
}

struct StateIndicatorPreview: View {
    let option: IslandSessionStateIndicator

    var body: some View {
        HStack(spacing: 8) {
            indicator
            IslandThemes.current.shape(cornerRadius: 2)
                .fill(V6Palette.paper.opacity(option == .tint ? 0.55 : 0.22))
                .frame(width: 58, height: 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            IslandThemes.current.shape(cornerRadius: 8)
                .fill(option == .tint ? Color(hex: AgentTool.codex.brandColorHex)?.opacity(0.22) ?? V6Palette.paper.opacity(0.08) : Color.clear)
        )
    }

    @ViewBuilder
    private var indicator: some View {
        let color = Color(hex: AgentTool.codex.brandColorHex) ?? V6Palette.paper
        switch option {
        case .animatedDot:
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .shadow(color: color.opacity(0.55), radius: 5)
        case .bar:
            IslandThemes.current.shape(cornerRadius: 2)
                .fill(color)
                .frame(width: 4, height: 28)
        case .glyph:
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
        case .tint:
            Circle()
                .fill(V6Palette.paper.opacity(0.72))
                .frame(width: 10, height: 10)
        }
    }
}

struct UsageDisplayPreview: View {
    let option: IslandUsageDisplay

    var body: some View {
        HStack(spacing: 6) {
            if option == .compact {
                usageChip("Cl", window: "5h", value: 42, color: Color(hex: AgentTool.claudeCode.brandColorHex) ?? .orange)
                usageChip("Cx", window: "7d", value: 13, color: Color(hex: AgentTool.codex.brandColorHex) ?? .blue)
            } else {
                IslandThemes.current.shape(cornerRadius: 2)
                    .fill(V6Palette.paper.opacity(0.18))
                    .frame(width: 72, height: 5)
            }
        }
        .frame(width: 104, alignment: .center)
    }

    private func usageChip(_ title: String, window: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(V6Palette.paper.opacity(0.66))
            Text(window)
                .font(.islandMono(size: 9, weight: .semibold))
                .foregroundStyle(V6Palette.paper.opacity(0.42))
            Text("\(value)%")
                .font(.islandMono(size: 9.5, weight: .bold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(V6Palette.paper.opacity(0.055), in: Capsule())
    }
}

struct SessionGroupPreview: View {
    let option: IslandSessionGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch option {
            case .none:
                previewLine(width: 72, color: V6Palette.paper.opacity(0.42))
                previewLine(width: 54, color: V6Palette.paper.opacity(0.28))
                previewLine(width: 64, color: V6Palette.paper.opacity(0.22))
            case .state:
                groupBlock(width: 52)
                groupBlock(width: 70)
            case .agent:
                agentBlock(color: Color(hex: AgentTool.claudeCode.brandColorHex) ?? V6Palette.paper)
                agentBlock(color: Color(hex: AgentTool.codex.brandColorHex) ?? V6Palette.paper)
            case .project:
                groupBlock(width: 76)
                groupBlock(width: 46)
            }
        }
        .frame(width: 84, alignment: .leading)
    }

    private func previewLine(width: CGFloat, color: Color) -> some View {
        IslandThemes.current.shape(cornerRadius: 2)
            .fill(color)
            .frame(width: width, height: 5)
    }

    private func groupBlock(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            previewLine(width: width * 0.48, color: V6Palette.paper.opacity(0.48))
            previewLine(width: width, color: V6Palette.paper.opacity(0.22))
        }
    }

    private func agentBlock(color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            previewLine(width: 54, color: V6Palette.paper.opacity(0.25))
        }
    }
}

struct SessionSortPreview: View {
    let option: IslandSessionSort

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    Text(rows[index].rank)
                        .font(.islandMono(size: 9, weight: .semibold))
                        .foregroundStyle(V6Palette.paper.opacity(0.55))
                        .frame(width: 12, alignment: .leading)
                    IslandThemes.current.shape(cornerRadius: 2)
                        .fill(rows[index].color)
                        .frame(width: rows[index].width, height: 5)
                }
            }
        }
        .frame(width: 82, alignment: .leading)
    }

    private var rows: [(rank: String, width: CGFloat, color: Color)] {
        switch option {
        case .attention:
            return [
                ("!", 62, Color(hex: AgentTool.claudeCode.brandColorHex) ?? V6Palette.paper),
                ("2", 48, V6Palette.paper.opacity(0.28)),
                ("3", 58, V6Palette.paper.opacity(0.2)),
            ]
        case .lastUpdate:
            return [
                ("1", 64, V6Palette.paper.opacity(0.38)),
                ("2", 56, V6Palette.paper.opacity(0.3)),
                ("3", 42, V6Palette.paper.opacity(0.22)),
            ]
        }
    }
}
