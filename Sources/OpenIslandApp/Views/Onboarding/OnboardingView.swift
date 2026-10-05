import SwiftUI
import OpenIslandCore

/// Three short steps; practice answers never leave this view.
struct OnboardingView: View {
    var model: AppModel
    @State private var flow = OnboardingFlow()
    @State private var practice = OnboardingPractice()

    private var lang: LanguageManager { model.lang }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
            }
            Divider().overlay(V6Palette.paper.opacity(0.12))
            controls
        }
        .foregroundStyle(V6Palette.paper)
        .background(IslandThemes.current.ink)
        .preferredColorScheme(.dark)
        .frame(width: 520, height: 520)
        .onChange(of: flow.isFinished) { _, finished in
            guard finished else { return }
            model.completeOnboarding()
            model.notchOpen(reason: .click, surface: .sessionList())
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: flow.step.symbolName)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(IslandThemes.current.accent)
                .accessibilityHidden(true)
            Text(lang.t(flow.step.titleKey))
                .font(.system(size: 21, weight: .semibold))
            Text(lang.t(flow.step.bodyKey))
                .font(.islandDecision(size: 13))
                .foregroundStyle(V6Palette.paper.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            if flow.step == .detection {
                detectionStatus
            } else if flow.step == .finish {
                practiceQuestion
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var installedHookNames: [String] {
        [("Claude Code", model.claudeHooksInstalled), ("Codex CLI", model.codexHooksInstalled),
         ("Cursor", model.cursorHooksInstalled), ("OpenCode", model.hooks.openCodePluginInstalled),
         ("Gemini CLI", model.geminiHooksInstalled), ("Qoder", model.qoderHooksInstalled),
         ("Qwen Code", model.qwenCodeHooksInstalled), ("Factory", model.factoryHooksInstalled),
         ("CodeBuddy", model.codebuddyHooksInstalled), ("Kimi", model.kimiHooksInstalled)]
            .compactMap { $0.1 ? $0.0 : nil } + (model.paseoConnectionState == .connected ? ["Paseo"] : [])
    }

    private var detectionStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(installedHookNames.isEmpty
                ? lang.t("onboarding.connection.none")
                : lang.t("onboarding.connection.installed", installedHookNames.joined(separator: ", ")),
                systemImage: installedHookNames.isEmpty ? "link" : "checkmark.circle")
                .font(.islandDecision(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            Text(lang.t("onboarding.connection.hooksScope"))
                .font(.islandDecision(size: 13))
                .foregroundStyle(V6Palette.paper.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
            Button(lang.t("onboarding.connection.settings")) {
                model.showSettings(tab: "integrations")
            }
            .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true, surface: .decisionCard))
        }
    }

    private var practiceOptions: [String] {
        [lang.t("onboarding.practice.optionA"), lang.t("onboarding.practice.optionB")]
    }

    @ViewBuilder private var practiceQuestion: some View {
        if practice.isComplete {
            Label(lang.t("onboarding.practice.complete"), systemImage: "checkmark.circle.fill")
                .font(.islandDecision(size: 14, weight: .medium))
                .foregroundStyle(V6Palette.paper)
                .padding(.vertical, 12)
        } else {
            StructuredQuestionPromptView(prompt: QuestionPrompt(title: lang.t("onboarding.practice.question"),
                questions: [QuestionPromptItem(question: lang.t("onboarding.practice.question"),
                    header: lang.t("onboarding.practice.header"),
                    options: practiceOptions.map { QuestionOption(label: $0) },
                    answerKey: OnboardingPractice.answerKey)]), lang: lang, allowsUnstructuredReply: false) { response in
                practice.answer(response, allowedAnswers: practiceOptions)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button(lang.t("onboarding.skip")) { flow.skip() }
                .buttonStyle(.plain)
                .foregroundStyle(V6Palette.paper.opacity(0.82))
            Spacer()
            Text(flow.progressText)
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(V6Palette.paper.opacity(0.82))
            if flow.canGoBack {
                Button(lang.t("onboarding.back")) { flow.goBack() }
                    .buttonStyle(IslandActionButtonStyle(kind: .secondary, surface: .decisionCard))
            }
            Button(lang.t(flow.step.isLast ? "onboarding.openIsland" : "onboarding.next")) {
                flow.advance()
            }
            .buttonStyle(IslandActionButtonStyle(kind: .primary, surface: .decisionCard))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }
}
