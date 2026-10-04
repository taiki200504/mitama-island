import SwiftUI
import OpenIslandCore

extension IslandSessionRow {
    @ViewBuilder
    var approvalActionBody: some View {
        if isPaseo { paseoApprovalActionBody } else {
        VStack(alignment: .leading, spacing: 8) {
            if !isPlanApproval {
                riskBanner(PermissionRisk.of(toolName: session.permissionRequest?.toolName))
            }

            HStack(spacing: 6) {
                Text(lang.t(isPlanApproval ? "approval.planReady" : "approval.toolPermissionRequested"))
                    .saoCaps(size: 12.5, text: lang.t(isPlanApproval ? "approval.planReady" : "approval.toolPermissionRequested"))
                    .foregroundStyle(SAOGrammar.Palette.ink.opacity(0.86))

                if pendingApprovalCount > 1 {
                    Text(lang.t("approval.pendingCount", String(pendingApprovalCount)))
                        .font(.islandMono(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(SAOGrammar.Palette.ink.opacity(0.1), in: Capsule())
                        .foregroundStyle(SAOGrammar.Palette.ink.opacity(0.6))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(commandPreviewText)
                    .font(.islandMono(size: 11.5, weight: .semibold))
                    .foregroundStyle(SAOGrammar.Palette.ink.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)

                if let path = session.permissionRequest?.affectedPath.trimmedForNotificationCard,
                   !path.isEmpty {
                    Text(path)
                        .font(.islandText(size: 10.5, weight: .medium))
                        .foregroundStyle(SAOGrammar.Palette.ink.opacity(0.42))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                IslandThemes.current.shape(cornerRadius: 7)
                    .fill(SAOGrammar.Palette.ink.opacity(0.06))
            )

            HStack(spacing: 8) {
                Button(shortcutHinted(session.permissionRequest?.secondaryActionTitle ?? lang.t("approval.deny"), .deny)) {
                    onApprove?(.deny)
                }
                .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true, surface: .lightCard))
                Button(shortcutHinted(session.permissionRequest?.primaryActionTitle ?? lang.t("approval.allowOnce"), .approve)) {
                    onApprove?(.allowOnce)
                }
                // The card's own primary action, not a warning — the
                // selection gradient carries "this is the one you want" the
                // way it does everywhere else in this grammar.
                .buttonStyle(IslandActionButtonStyle(kind: .primary, expands: true, surface: .lightCard))
            }

            // Whatever else the agent offered — "bypass permissions",
            // "accept edits", a scoped always-allow. These arrive in
            // `suggestedUpdates` and used to be dropped on the floor, which left
            // the island unable to answer a plan-mode exit at all.
            ForEach(Array(suggestedApprovalUpdates.enumerated()), id: \.offset) { _, update in
                Button(update.displayLabel) {
                    onApprove?(.allowWithUpdates([update]))
                }
                .buttonStyle(IslandActionButtonStyle(kind: .primary, expands: true, surface: .lightCard))
            }

            // Only worth offering when there is more than one thing queued.
            if pendingApprovalCount > 1 {
                HStack(spacing: 8) {
                    Button(lang.t("approval.denyAll")) { onResolveAll?(.deny) }
                        .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true, surface: .lightCard))
                    Button(lang.t("approval.allowAll")) { onResolveAll?(.allowOnce) }
                        .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true, surface: .lightCard))
                }
            }

            Button(shortcutHinted(lang.t("approval.goToTerminal"), .jumpToTerminal)) { onJump() }
                .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true, surface: .lightCard))
        }
        .padding(10)
        .saoCard()
        // A red edge for anything that changes the machine. A soft halo was
        // the first try and it bled through the white card until the whole
        // thing read pink; a line stays outside the paper.
        .overlay(
            SAOPanelShape(cornerRadius: 10, cutDepth: 14)
                .stroke(SAOGrammar.Palette.danger.opacity(approvalIsElevated ? 0.7 : 0), lineWidth: 1.5)
        )
        .shadow(color: approvalIsElevated ? SAOGrammar.Palette.danger.opacity(0.28) : .clear, radius: 6)
        }
    }

    var isPaseo: Bool { session.jumpTarget?.terminalApp == "Paseo" }

    private var paseoContextHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Paseo · \(session.tool.displayName)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SAOGrammar.Palette.ink.opacity(0.9))
            Text("\(session.jumpTarget?.workspaceName ?? "") · \(session.title)")
                .font(.system(size: 12))
                .foregroundStyle(SAOGrammar.Palette.ink.opacity(0.8))
                .lineLimit(2)
            Text("現在のモード: \(paseoModeLabel ?? session.permissionRequest?.paseoContext?.currentModeLabel ?? "モード情報なし")")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SAOGrammar.Palette.ink.opacity(0.86))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var paseoApprovalActionBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("実行の許可")
                .font(.system(size: 15, weight: .semibold))
            paseoContextHeader
            Text(session.permissionRequest?.toolName ?? "要求")
                .font(.system(size: 13, weight: .semibold))
            Text(session.permissionRequest?.summary ?? session.summary)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text("この要求についてだけ回答します。追加の許可はPaseoが提示した範囲に限られます。")
                .font(.system(size: 12))
                .foregroundStyle(SAOGrammar.Palette.ink.opacity(0.8))

            if session.permissionRequest?.requiresTerminalApproval != true {
                let context = session.permissionRequest?.paseoContext
                if let context, !context.actions.isEmpty {
                    ForEach(context.actions) { action in
                        Button(paseoActionLabel(action)) {
                            onApprove?(.paseoAction(requestID: context.requestID, actionID: action.id))
                        }
                        .buttonStyle(IslandActionButtonStyle(kind: action.variant == "primary" ? .primary : .secondary,
                                                            expands: true, surface: .lightCard))
                        if action.intent == "implement" {
                            Text("実行時の権限は編集の自動許可（acceptEdits）へ変わります。")
                                .font(.system(size: 12)).foregroundStyle(SAOGrammar.Palette.ink.opacity(0.8))
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Button("拒否") { onApprove?(.deny) }
                            .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true, surface: .lightCard))
                        Button("今回だけ許可") { onApprove?(.allowOnce) }
                            .buttonStyle(IslandActionButtonStyle(kind: .primary, expands: true, surface: .lightCard))
                    }
                }
                ForEach(Array((session.permissionRequest?.suggestedUpdates ?? []).enumerated()), id: \.offset) { _, update in
                    Button(update.displayLabel) { onApprove?(.allowWithUpdates([update])) }
                        .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true, surface: .lightCard))
                }
            } else {
                Text("この種類の要求はPaseo側で内容を確認して回答してください。")
                    .font(.system(size: 13))
            }
            if submissionIsSending {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Paseoへ送信中…") }
                    .font(.system(size: 12))
            }
            if let submissionError {
                Text(submissionError).font(.system(size: 12)).foregroundStyle(SAOGrammar.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Paseoでこの会話を開く", action: onExplicitJump ?? onJump)
                .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true, surface: .lightCard))
        }
        .foregroundStyle(SAOGrammar.Palette.ink.opacity(0.92))
        .padding(12)
        .saoCard()
        .disabled(submissionIsSending)
    }

    private func paseoActionLabel(_ action: PaseoPermissionAction) -> String {
        if action.behavior == "deny" { return "拒否" }
        if action.intent == "implement_resume" { return "元のBypassを維持して実行" }
        if action.intent == "implement" { return "計画を実行する" }
        return action.label
    }

    private var approvalIsElevated: Bool {
        !isPlanApproval && PermissionRisk.of(toolName: session.permissionRequest?.toolName) == .elevated
    }

    /// The system-message strip across the top of the card: hazard stripes and
    /// a caution for anything that writes, runs or deletes; a quiet tag for
    /// tools that only look. Same classification the voice gate uses, so the
    /// card and the second "yes" never disagree about what is dangerous.
    @ViewBuilder
    private func riskBanner(_ risk: PermissionRisk) -> some View {
        switch risk {
        case .elevated:
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("WARNING")
                    .saoCaps(size: 11.5, text: "WARNING")
                Text(lang.t("approval.risk.elevated"))
                    .font(.islandText(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                ZStack {
                    SAOGrammar.Palette.danger
                    HazardStripes()
                        .fill(Color.black.opacity(0.16))
                }
                .clipShape(Self.bannerShape)
            )
            .overlay(Self.bannerShape.stroke(Color.black.opacity(0.35), lineWidth: 1))
            .accessibilityElement(children: .combine)
        case .ordinary:
            HStack(spacing: 5) {
                Image(systemName: "eye")
                    .font(.system(size: 9, weight: .semibold))
                Text(lang.t("approval.risk.ordinary"))
                    .font(.islandMono(size: 9.5, weight: .semibold))
            }
            .foregroundStyle(SAOGrammar.Palette.systemCyan)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Self.bannerShape.fill(SAOGrammar.Palette.systemCyan.opacity(0.12)))
            .overlay(Self.bannerShape.stroke(SAOGrammar.Palette.systemCyan.opacity(0.4), lineWidth: 0.75))
            .accessibilityElement(children: .combine)
        }
    }

    private static let bannerShape = SAOPanelShape(cornerRadius: 3, cuts: [.topLeading, .bottomTrailing], cutDepth: 6)

    /// Appends the key that also triggers this button, but only while the
    /// modifier is held — a permanent "⌃Y" on every button is clutter, and one
    /// that appears on demand is a reminder.
    private func shortcutHinted(_ title: String, _ action: PanelShortcutAction) -> String {
        guard let hint = shortcutHint else { return title }
        return "\(title)  \(hint.modifier.symbol)\(hint.key(for: action))"
    }

    /// The agent's own options, falling back to a session-scoped always-allow
    /// when it offered none — which is what the card used to hard-code.
    ///
    /// The mode choices are appended when the agent left them out, because it
    /// only volunteers those for mode-shaped prompts like a plan-mode exit, and
    /// without them the island cannot answer "stop asking" at all. They go last,
    /// widest-reaching at the bottom, so the safe answers stay under the cursor.
    private var suggestedApprovalUpdates: [ClaudePermissionUpdate] {
        var options = session.permissionRequest?.suggestedUpdates ?? []

        if options.isEmpty, let toolName = session.permissionRequest?.toolName {
            options.append(
                .addRules(
                    destination: .session,
                    rules: [ClaudePermissionRuleValue(toolName: toolName)],
                    behavior: .allow
                )
            )
        }

        for mode in [ClaudePermissionMode.acceptEdits, .bypassPermissions] {
            guard !options.contains(where: { $0.setsPermissionMode(mode) }),
                  let update = session.permissionModeUpdate(for: mode) else { continue }
            options.append(update)
        }

        return options
    }

    var questionActionBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isPaseo {
                VStack(alignment: .leading, spacing: 7) {
                    Text("質問への回答").font(.system(size: 15, weight: .semibold))
                    paseoContextHeader
                }
                .foregroundStyle(SAOGrammar.Palette.ink.opacity(0.92))
                .padding(12).saoCard()
            }
            StructuredQuestionPromptView(
                prompt: session.questionPrompt, lang: lang, isPaseo: isPaseo,
                isSending: submissionIsSending, errorMessage: submissionError,
                onAnswer: { onAnswer?($0) }
            )
            if isPaseo {
                Button("Paseoでこの会話を開く", action: onExplicitJump ?? onJump)
                    .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true, surface: .lightCard))
            }
        }
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
