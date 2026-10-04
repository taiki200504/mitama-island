import SwiftUI
import OpenIslandCore

struct StructuredQuestionPromptView: View {
    let prompt: QuestionPrompt?
    var lang: LanguageManager = .shared
    var isPaseo = false
    var isSending = false
    var errorMessage: String?
    var allowsUnstructuredReply = true
    let onAnswer: (QuestionPromptResponse) -> Void

    @State private var selections: [String: Set<String>] = [:]
    @State private var freeformTexts: [String: String] = [:]
    @State private var typedReply: String = ""
    @State private var hoveredOptionKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lang.t("decision.question.title"))
                .font(.islandDecision(size: 15, weight: .semibold))
            if showsPromptTitle {
                Text(promptTitle)
                    .font(.islandDecision(size: 14, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if requiresPaseoQuestionHandoff {
                Text(lang.t("decision.paseo.questionUnsupported"))
                    .font(.islandDecision(size: 13))
                    .foregroundStyle(V6Palette.paper.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            } else if structuredQuestions.isEmpty {
                freeformAnswerBody
                    .transition(IslandTransition.resolved(IslandTransition.modal))
            } else {
                Group {
                    // Deliberately every question at once rather than one per
                    // page. The panel already scrolls, and paging hides how
                    // much is left to answer — which is the thing the user
                    // wants to know.
                    if structuredQuestions.count > 1 {
                        Text(lang.t(
                            "question.progress",
                            String(answeredQuestionCount),
                            String(structuredQuestions.count)
                        ))
                        .font(.islandDecision(size: 12))
                        .foregroundStyle(V6Palette.paper.opacity(0.78))
                    }

                    // Only the questions scroll. The submit button below stays
                    // put: with a long list it used to be pushed off the
                    // bottom of the card with no way to reach it, which left
                    // the question unanswerable from the island at all.
                    AutoHeightScrollView(maxHeight: min(IslandChromeMetrics.questionOptionListMaxHeight,
                        max(100, SettingsStore.shared.display.maxPanelHeight - 360))) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(structuredQuestions, id: \.responseKey) { question in
                                questionRow(question)
                            }
                        }
                    }

                    quickReplyField

                    // Says why the button is inert instead of leaving the
                    // user to hunt for the question they missed.
                    if !canSubmit, answeredQuestionCount < structuredQuestions.count {
                        Text(lang.t("question.answerAllFirst"))
                            .font(.islandDecision(size: 12))
                            .foregroundStyle(IslandDesignPalette.Status.waitingForAnswer.opacity(0.8))
                    }

                    Button(submitButtonTitle) {
                        submitAnswer()
                    }
                    .buttonStyle(IslandActionButtonStyle(kind: canSubmit ? .primary : .secondary, expands: true, surface: .decisionCard))
                    .disabled(isSending || !canSubmit)
                }
                .transition(IslandTransition.resolved(IslandTransition.modal))
            }
        }
        .disabled(isSending)
        .overlay(alignment: .bottomTrailing) {
            if isSending { ProgressView().controlSize(.small).padding(10) }
        }
        .safeAreaInset(edge: .bottom, spacing: 6) {
            if let errorMessage {
                Text(errorMessage).font(.system(size: 12)).foregroundStyle(SAOGrammar.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 10)
            } else if isSending {
                Text(isPaseo ? lang.t("decision.paseo.sending") : lang.t("decision.question.sending")).font(.system(size: 12)).foregroundStyle(V6Palette.paper)
            }
        }
        .foregroundStyle(V6Palette.paper)
        .frame(maxWidth: .infinity, alignment: .leading)
        .islandDecisionCard()
    }

    // MARK: - Per-question row

    /// Renders a single question with its header, text, and vertical option list.
    @ViewBuilder
    private func questionRow(_ question: QuestionPromptItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if structuredQuestions.count > 1 {
                Text(question.header)
                    .font(.islandDecision(size: 12, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.78))
            }

            Text(question.question)
                .font(.islandDecision(size: 14, weight: .medium))
                .foregroundStyle(V6Palette.paper.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)

            Text(question.multiSelect ? lang.t("decision.option.multiple") : lang.t("decision.option.single"))
                .font(.islandDecision(size: 12))
                .foregroundStyle(V6Palette.paper.opacity(0.78))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(question.options.enumerated()), id: \.element.id) { index, option in
                    optionRow(option, optionIndex: index, question: question)
                }
            }
        }
    }

    // MARK: - Option row (vertical, CLI-style)

    @ViewBuilder
    private func optionRow(
        _ option: QuestionOption,
        optionIndex: Int,
        question: QuestionPromptItem
    ) -> some View {
        let isSelected = selectedLabels(for: question).contains(option.label)
        let key = optionKey(for: question, option: option)
        let isHovered = hoveredOptionKey == key
        let showsFreeform = option.allowsFreeform && isSelected
        VStack(alignment: .leading, spacing: 0) {
            Button {
                toggle(option: option.label, for: question)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: question.multiSelect
                        ? (isSelected ? "checkmark.square.fill" : "square")
                        : (isSelected ? "largecircle.fill.circle" : "circle"))
                        .font(.system(size: 16))
                        .foregroundStyle(isSelected ? IslandThemes.current.accent : V6Palette.paper.opacity(0.78))
                        .frame(width: 22)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(option.label)
                            .font(.islandDecision(size: 13, weight: .medium))
                            .foregroundStyle(V6Palette.paper.opacity(isSelected ? 1 : 0.78))

                        if !option.description.isEmpty {
                            Text(option.description)
                                .font(.islandDecision(size: 12))
                                .foregroundStyle(V6Palette.paper.opacity(0.78))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.islandText(size: 11, weight: .bold))
                            .foregroundStyle(IslandDesignPalette.Status.completed)
                    }
                }
                .contentShape(Rectangle())
                .padding(.vertical, 5)
                .padding(.horizontal, 11)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(option.label)
            .accessibilityValue(isSelected ? lang.t("decision.option.selected") : lang.t("decision.option.unselected"))
            .accessibilityHint(option.description)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            if showsFreeform {
                Divider()
                    .overlay(V6Palette.paper.opacity(0.08))
                freeformField(for: option, question: question)
            }
        }
        .background(
            IslandThemes.current.shape(cornerRadius: 8)
                .fill(optionFillColor(isSelected: isSelected, isHovered: isHovered))
        )
        .overlay(
            IslandThemes.current.shape(cornerRadius: 8)
                .strokeBorder(optionStrokeColor(isSelected: isSelected, isHovered: isHovered))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                hoveredOptionKey = hovering ? key : (hoveredOptionKey == key ? nil : hoveredOptionKey)
            }
        }
    }

    @ViewBuilder
    private func freeformField(for option: QuestionOption, question: QuestionPromptItem) -> some View {
        let key = freeformKey(for: question, option: option)
        ReplyTextField(
            placeholder: lang.t("question.otherPlaceholder"),
            text: Binding(
                get: { freeformTexts[key] ?? "" },
                set: { freeformTexts[key] = $0 }
            ),
            onSubmit: {
                if !isSending, hasCompleteSelection {
                    onAnswer(QuestionPromptResponse(answers: answerMap))
                }
            },
            requestsInitialFocus: true
        )
        .frame(height: 22)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
    }

    private var freeformAnswerBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            quickReplyField

            Button(submitButtonTitle) {
                submitAnswer()
            }
            .buttonStyle(IslandActionButtonStyle(kind: canSubmit ? .primary : .secondary, expands: true, surface: .decisionCard))
            .disabled(isSending || !canSubmit)
        }
    }

    @ViewBuilder
    private var quickReplyField: some View {
        if showsGlobalReplyField {
            HStack(spacing: 6) {
                ReplyTextField(
                    placeholder: lang.t("question.otherPlaceholder"),
                    text: $typedReply,
                    onSubmit: {
                        if !isSending, canSubmit {
                            submitAnswer()
                        }
                    }
                )
                .frame(height: 30)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                IslandThemes.current.shape(cornerRadius: 10)
                    .fill(V6Palette.paper.opacity(0.035))
            )
            .overlay(
                IslandThemes.current.shape(cornerRadius: 10)
                    .strokeBorder(V6Palette.paper.opacity(0.055))
            )
        }
    }

    // MARK: - Helpers

    private var structuredQuestions: [QuestionPromptItem] {
        if let questions = prompt?.questions, !questions.isEmpty {
            return questions
        }

        guard let prompt, !prompt.options.isEmpty else {
            return []
        }

        return [
            QuestionPromptItem(
                question: prompt.title,
                header: lang.t("question.answerNeeded"),
                options: prompt.options.map { QuestionOption(label: $0) }
            ),
        ]
    }

    private var promptTitle: String {
        prompt?.title.trimmedForNotificationCard ?? lang.t("question.answerNeeded")
    }

    private var showsPromptTitle: Bool {
        guard !promptTitle.isEmpty else {
            return false
        }

        guard structuredQuestions.count == 1,
              let questionTitle = structuredQuestions.first?.question.trimmedForNotificationCard else {
            return true
        }

        return questionTitle.caseInsensitiveCompare(promptTitle) != .orderedSame
    }

    private var answerMap: [String: String] {
        Dictionary(uniqueKeysWithValues: structuredQuestions.compactMap { question in
            let values = resolvedAnswers(for: question)
            guard !values.isEmpty else {
                return nil
            }
            return (question.responseKey, values.joined(separator: ", "))
        })
    }

    private var trimmedReply: String {
        typedReply.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showsGlobalReplyField: Bool {
        allowsUnstructuredReply && (structuredQuestions.isEmpty || !structuredQuestions.contains { question in
            question.options.contains { $0.allowsFreeform }
        })
    }

    private var primarySelectedAnswer: String? {
        guard structuredQuestions.count == 1,
              let question = structuredQuestions.first else {
            return nil
        }

        let values = resolvedAnswers(for: question)
        guard !values.isEmpty else {
            return nil
        }

        return values.joined(separator: ", ")
    }

    var requiresPaseoQuestionHandoff: Bool {
        isPaseo && prompt?.questions.isEmpty == true
    }

    private var canSubmit: Bool {
        !requiresPaseoQuestionHandoff && (!trimmedReply.isEmpty || (!structuredQuestions.isEmpty && hasCompleteSelection))
    }

    private var submitButtonTitle: String {
        if isSending { return lang.t("decision.sending") }
        if errorMessage != nil { return lang.t("decision.question.retry") }
        if !trimmedReply.isEmpty {
            return lang.t("question.sendReply")
        }

        if let primarySelectedAnswer, !primarySelectedAnswer.isEmpty {
            return lang.t("question.sendAnswer")
        }

        return lang.t("question.submit")
    }

    private func submitAnswer() {
        guard !isSending, canSubmit else { return }
        if !trimmedReply.isEmpty {
            onAnswer(QuestionPromptResponse(answer: trimmedReply))
            return
        }

        onAnswer(
            QuestionPromptResponse(
                rawAnswer: primarySelectedAnswer,
                answers: answerMap
            )
        )
    }

    /// How many questions have a usable answer, for the progress line.
    var answeredQuestionCount: Int {
        structuredQuestions.filter(isAnswered).count
    }

    private func isAnswered(_ question: QuestionPromptItem) -> Bool {
        let selected = selectedLabels(for: question)
        guard !selected.isEmpty else { return false }
        for option in question.options where option.allowsFreeform && selected.contains(option.label) {
            if trimmedFreeform(for: question, option: option).isEmpty {
                return false
            }
        }
        return true
    }

    private var hasCompleteSelection: Bool {
        structuredQuestions.allSatisfy { question in
            let selected = selectedLabels(for: question)
            guard !selected.isEmpty else {
                return false
            }
            // When a freeform option is selected, require non-empty text.
            for option in question.options where option.allowsFreeform && selected.contains(option.label) {
                if trimmedFreeform(for: question, option: option).isEmpty {
                    return false
                }
            }
            return true
        }
    }

    private func selectedLabels(for question: QuestionPromptItem) -> Set<String> {
        selections[question.responseKey] ?? []
    }

    private func resolvedAnswers(for question: QuestionPromptItem) -> [String] {
        let selected = selectedLabels(for: question)
        guard !selected.isEmpty else { return [] }

        let optionOrder = question.options
        var answers: [String] = []
        for option in optionOrder where selected.contains(option.label) {
            if option.allowsFreeform {
                let text = trimmedFreeform(for: question, option: option)
                answers.append(text.isEmpty ? option.label : text)
            } else {
                answers.append(option.label)
            }
        }
        return answers
    }

    private func freeformKey(for question: QuestionPromptItem, option: QuestionOption) -> String {
        "\(question.responseKey)|\(option.label)"
    }

    private func optionKey(for question: QuestionPromptItem, option: QuestionOption) -> String {
        "\(question.responseKey)|\(option.label)"
    }

    private func optionFillColor(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return SAOGrammar.Palette.accentOrange.opacity(0.18)
        }
        if isHovered {
            return V6Palette.paper.opacity(0.065)
        }
        return V6Palette.paper.opacity(0.028)
    }

    private func optionStrokeColor(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return V6Palette.paper.opacity(0.36)
        }
        if isHovered {
            return V6Palette.paper.opacity(0.13)
        }
        return V6Palette.paper.opacity(0.045)
    }

    private func trimmedFreeform(for question: QuestionPromptItem, option: QuestionOption) -> String {
        (freeformTexts[freeformKey(for: question, option: option)] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func toggle(option: String, for question: QuestionPromptItem) {
        var selected = selections[question.responseKey] ?? []

        if question.multiSelect {
            if selected.contains(option) {
                selected.remove(option)
            } else {
                selected.insert(option)
            }
        } else {
            if selected.contains(option) {
                selected.removeAll()
            } else {
                selected = [option]
            }
        }

        typedReply = ""
        selections[question.responseKey] = selected
    }
}
