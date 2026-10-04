import SwiftUI
import OpenIslandCore

extension IslandSessionRow {
    @ViewBuilder
    var approvalActionBody: some View {
        if isPaseo { paseoApprovalActionBody } else {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(isPlanApproval ? lang.t("decision.plan.title") : lang.t("decision.approval.title"))
                    .font(.islandDecision(size: 15, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.86))

                if pendingApprovalCount > 1 {
                    Text(lang.t("approval.pendingCount", String(pendingApprovalCount)))
                        .font(.islandMono(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(V6Palette.paper.opacity(0.1), in: Capsule())
                        .foregroundStyle(V6Palette.paper.opacity(0.6))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(commandPreviewText)
                    .font(.islandDecision(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(V6Palette.paper.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)

                if let path = session.permissionRequest?.affectedPath.trimmedForNotificationCard,
                   !path.isEmpty {
                    Text(path)
                        .font(.islandDecision(size: 12))
                        .foregroundStyle(V6Palette.paper.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                IslandThemes.current.shape(cornerRadius: 7)
                    .fill(V6Palette.paper.opacity(0.06))
            )

            HStack(spacing: 8) {
                Button(shortcutHinted(session.permissionRequest?.secondaryActionTitle ?? lang.t("approval.deny"), .deny)) {
                    onApprove?(.deny)
                }
                .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true, surface: .decisionCard))
                Button(shortcutHinted(session.permissionRequest?.primaryActionTitle ?? lang.t("approval.allowOnce"), .approve)) {
                    onApprove?(.allowOnce)
                }
                // The card's own primary action, not a warning — the
                // selection gradient carries "this is the one you want" the
                // way it does everywhere else in this grammar.
                .buttonStyle(IslandActionButtonStyle(kind: .primary, expands: true, surface: .decisionCard))
            }

            Text(lang.t("decision.scope"))
                .font(.islandDecision(size: 12)).foregroundStyle(V6Palette.paper.opacity(0.78))

            // Whatever else the agent offered — "bypass permissions",
            // "accept edits", a scoped always-allow. These arrive in
            // `suggestedUpdates` and used to be dropped on the floor, which left
            // the island unable to answer a plan-mode exit at all.
            ForEach(Array(suggestedApprovalUpdates.enumerated()), id: \.offset) { _, update in
                Button(update.displayLabel) {
                    onApprove?(.allowWithUpdates([update]))
                }
                .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true, surface: .decisionCard))
            }

            // Only worth offering when there is more than one thing queued.
            if pendingApprovalCount > 1, onResolveAll != nil {
                HStack(spacing: 8) {
                    Button(lang.t("approval.denyAll")) { onResolveAll?(.deny) }
                        .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true, surface: .decisionCard))
                    Button(lang.t("approval.allowAll")) { onResolveAll?(.allowOnce) }
                        .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true, surface: .decisionCard))
                }
            }

            Button(shortcutHinted(lang.t("approval.goToTerminal"), .jumpToTerminal)) { onJump() }
                .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true, surface: .decisionCard))
        }
        .foregroundStyle(V6Palette.paper)
        .islandDecisionCard()
        }
    }

    var isPaseo: Bool { session.jumpTarget?.terminalApp == "Paseo" }

    private var paseoApprovalActionBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(lang.t("decision.approval.title"))
                .font(.islandDecision(size: 15, weight: .semibold))
            Text(session.permissionRequest?.toolName ?? lang.t("decision.request"))
                .font(.islandDecision(size: 13, weight: .semibold))
            Text(session.permissionRequest?.summary ?? session.summary)
                .font(.islandDecision(size: 13))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let path = session.permissionRequest?.affectedPath.trimmedForNotificationCard, !path.isEmpty {
                Text(path).font(.islandDecision(size: 12))
                    .foregroundStyle(V6Palette.paper.opacity(0.78))
                    .textSelection(.enabled).lineLimit(2).help(path)
            }
            Text(lang.t("decision.paseo.scope"))
                .font(.islandDecision(size: 12))
                .foregroundStyle(V6Palette.paper.opacity(0.8))

            if session.permissionRequest?.requiresTerminalApproval != true {
                Group {
                let context = session.permissionRequest?.paseoContext
                if let context, !context.actions.isEmpty {
                    ForEach(context.actions) { action in
                        Button(paseoActionLabel(action)) {
                            onApprove?(.paseoAction(requestID: context.requestID, actionID: action.id))
                        }
                        .buttonStyle(IslandActionButtonStyle(kind: action.id == preferredPaseoActionID ? .primary : .secondary,
                                                            expands: true, surface: .decisionCard))
                        if action.intent == "implement" {
                            Text(lang.t("decision.plan.acceptEdits"))
                                .font(.islandDecision(size: 12)).foregroundStyle(V6Palette.paper.opacity(0.8))
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Button(lang.t("decision.deny")) { onApprove?(.deny) }
                            .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true, surface: .decisionCard))
                        Button(lang.t("decision.allowOnce")) { onApprove?(.allowOnce) }
                            .buttonStyle(IslandActionButtonStyle(kind: .primary, expands: true, surface: .decisionCard))
                    }
                }
                ForEach(Array((session.permissionRequest?.suggestedUpdates ?? []).enumerated()), id: \.offset) { _, update in
                    Button(update.displayLabel) { onApprove?(.allowWithUpdates([update])) }
                        .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true, surface: .decisionCard))
                }
                }
                .disabled(submissionIsSending)
            } else {
                Text(lang.t("decision.paseo.unsupported"))
                    .font(.islandDecision(size: 13))
            }
            if submissionIsSending {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(lang.t("decision.paseo.sending")) }
                    .font(.islandDecision(size: 12))
            }
            if let submissionError {
                Text(submissionError).font(.islandDecision(size: 12)).foregroundStyle(SAOGrammar.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(lang.t("decision.paseo.open"), action: onExplicitJump ?? onJump)
                .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true, surface: .decisionCard))
        }
        .foregroundStyle(V6Palette.paper.opacity(0.92))
        .islandDecisionCard()
    }

    private func paseoActionLabel(_ action: PaseoPermissionAction) -> String {
        if action.behavior == "deny" { return lang.t("decision.deny") }
        if action.intent == "implement_resume" { return lang.t("decision.plan.resume") }
        if action.intent == "implement" { return lang.t("decision.plan.implement") }
        return action.label
    }

    /// Appends the key that also triggers this button, but only while the
    /// modifier is held — a permanent "⌃Y" on every button is clutter, and one
    /// that appears on demand is a reminder.
    private func shortcutHinted(_ title: String, _ action: PanelShortcutAction) -> String {
        guard let hint = shortcutHint else { return title }
        return "\(title)  \(hint.modifier.symbol)\(hint.key(for: action))"
    }

    var suggestedApprovalUpdates: [ClaudePermissionUpdate] {
        session.permissionRequest?.suggestedUpdates ?? []
    }

    private var preferredPaseoActionID: String? {
        let actions = session.permissionRequest?.paseoContext?.actions ?? []
        return actions.first(where: { $0.intent == "implement_resume" })?.id
            ?? actions.first(where: { $0.variant == "primary" && $0.behavior == "allow" })?.id
    }

    var questionActionBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let source = forwardedQuestionSourceTitle?.trimmedForNotificationCard, !source.isEmpty {
                Text(lang.t("decision.paseo.forwardedQuestion", source))
                    .font(.islandDecision(size: 12, weight: .medium))
                    .foregroundStyle(V6Palette.paper.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }

            StructuredQuestionPromptView(
                prompt: session.questionPrompt, lang: lang, isPaseo: isPaseo,
                isSending: submissionIsSending, errorMessage: submissionError,
                onAnswer: { onAnswer?($0) }
            )
            .id(session.questionPrompt?.id)
            if isPaseo {
                Button(questionConversationActionTitle, action: onExplicitJump ?? onJump)
                    .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true, surface: .decisionCard))
            }
        }
    }

    var questionConversationActionTitle: String {
        let forwarded = forwardedQuestionSourceTitle?.trimmedForNotificationCard.isEmpty == false
        return lang.t(forwarded ? "decision.paseo.forwardedOpen" : "decision.paseo.open")
    }

    private var commandLabel: String {
        switch session.currentToolName {
        case "exec_command", "Bash": return "Bash"
        case "AskUserQuestion": return "Question"
        case "ExitPlanMode": return "Plan"
        case "apply_patch": return "Patch"
        case "write_stdin": return "Input"
        case let value?: return AgentSession.currentToolDisplayName(for: value)
        case nil: return "Command"
        }
    }

    private var commandPreviewText: String {
        let preview = session.currentCommandPreviewText?.trimmedForNotificationCard
        if let preview, !preview.isEmpty {
            // A shell prompt in front of a plan reads as a command to run.
            return isPlanApproval ? preview : "$ \(preview)"
        }
        return session.permissionRequest?.summary.trimmedForNotificationCard ?? session.summary.trimmedForNotificationCard
    }

    /// Leaving plan mode is a decision about how to proceed, not a tool call.
    private var isPlanApproval: Bool {
        session.permissionRequest?.toolName == "ExitPlanMode"
    }

}

/// Diagonal warning stripes, drawn once as a path rather than repeated views.
private struct HazardStripes: Shape {
    var spacing: CGFloat = 9
    var width: CGFloat = 4.5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + width, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + width + rect.height, y: rect.minY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            path.closeSubpath()
            x += spacing
        }
        return path
    }
}
