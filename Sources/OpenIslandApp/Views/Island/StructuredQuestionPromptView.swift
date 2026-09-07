import SwiftUI
import OpenIslandCore

struct StructuredQuestionPromptView: View {
    let prompt: QuestionPrompt?
    var lang: LanguageManager = .shared
    let onAnswer: (QuestionPromptResponse) -> Void

    @State private var selections: [String: Set<String>] = [:]
    @State private var freeformTexts: [String: String] = [:]
    @State private var typedReply: String = ""
    @State private var hoveredOptionKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsPromptTitle {
                Text(promptTitle)
                    .font(.islandText(size: 13, weight: .semibold))
                    .foregroundStyle(IslandDesignPalette.Status.waitingForAnswer)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if structuredQuestions.isEmpty {
                freeformAnswerBody
            } else {
                // Deliberately every question at once rather than one per page.
                // The panel already scrolls, and paging hides how much is left
                // to answer — which is the thing the user wants to know.
                if structuredQuestions.count > 1 {
                    Text(lang.t(
                        "question.progress",
                        String(answeredQuestionCount),
                        String(structuredQuestions.count)
                    ))
                    .font(.islandMono(size: 10, weight: .medium))
                    .foregroundStyle(V6Palette.paper.opacity(0.5))
                }

                // Only the questions scroll. The submit button below stays put:
                // with a long list it used to be pushed off the bottom of the
                // card with no way to reach it, which left the question
                // unanswerable from the island at all.
                AutoHeightScrollView(maxHeight: IslandChromeMetrics.questionOptionListMaxHeight) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(structuredQuestions, id: \.question) { question in
                            questionRow(question)
                        }
                    }
                }

                quickReplyField

                // Says why the button is inert instead of leaving the user to
                // hunt for the question they missed.
                if !canSubmit, answeredQuestionCount < structuredQuestions.count {
                    Text(lang.t("question.answerAllFirst"))
                        .font(.islandText(size: 10.5, weight: .medium))
                        .foregroundStyle(IslandDesignPalette.Status.waitingForAnswer.opacity(0.8))
                }

                Button(submitButtonTitle) {
                    submitAnswer()
                }
                .buttonStyle(IslandActionButtonStyle(kind: canSubmit ? .primary : .secondary, expands: true))
                .disabled(!canSubmit)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            IslandThemes.current.shape(cornerRadius: 10)
                .fill(V6Palette.paper.opacity(0.03))
        )
        .overlay(
            IslandThemes.current.shape(cornerRadius: 10)
                .strokeBorder(V6Palette.paper.opacity(0.05))
        )
    }

    // MARK: - Per-question row

    /// Renders a single question with its header, text, and vertical option list.
    @ViewBuilder
    private func questionRow(_ question: QuestionPromptItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if structuredQuestions.count > 1 {
                Text(question.header)
                    .font(.islandText(size: 10, weight: .bold))
                    .foregroundStyle(V6Palette.paper.opacity(0.5))
            }

            Text(question.question)
                .font(.islandText(size: 12, weight: .medium))
                .foregroundStyle(V6Palette.paper.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
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
                    Text("\(optionIndex + 1)")
                        .font(.islandMono(size: 10.5, weight: .semibold))
                        .foregroundStyle(isSelected ? .black.opacity(0.82) : V6Palette.paper.opacity(0.42))
                        .frame(width: 22, height: 20)
                        .background(
                            IslandThemes.current.shape(cornerRadius: 5)
                                .fill(isSelected ? V6Palette.paper.opacity(0.88) : V6Palette.paper.opacity(0.045))
                        )
                        .overlay(
                            IslandThemes.current.shape(cornerRadius: 5)
                                .strokeBorder(V6Palette.paper.opacity(isSelected ? 0 : 0.08))
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(option.label)
                            .font(.islandText(size: 12.2, weight: .medium))
                            .foregroundStyle(V6Palette.paper.opacity(isSelected ? 1 : 0.78))

                        if !option.description.isEmpty {
                            Text(option.description)
                                .font(.islandText(size: 10.5))
                                .foregroundStyle(V6Palette.paper.opacity(isHovered || isSelected ? 0.48 : 0.38))
                                .lineLimit(1)
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
                if hasCompleteSelection {
                    onAnswer(QuestionPromptResponse(answers: answerMap))
                }
            }
        )
        .frame(height: 22)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
    }

    private var freeformAnswerBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            quickReplyField

            Button(lang.t("question.submit")) {
                submitAnswer()
            }
            .buttonStyle(IslandActionButtonStyle(kind: canSubmit ? .primary : .secondary, expands: true))
            .disabled(!canSubmit)
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
                        if canSubmit {
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
            return (question.question, values.joined(separator: ", "))
        })
    }

    private var trimmedReply: String {
        typedReply.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showsGlobalReplyField: Bool {
        structuredQuestions.isEmpty || !structuredQuestions.contains { question in
            question.options.contains { $0.allowsFreeform }
        }
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

    private var canSubmit: Bool {
        !trimmedReply.isEmpty || (!structuredQuestions.isEmpty && hasCompleteSelection)
    }

    private var submitButtonTitle: String {
        if !trimmedReply.isEmpty {
            return lang.t("question.sendReply")
        }

        if let primarySelectedAnswer, !primarySelectedAnswer.isEmpty {
            return lang.t("question.sendAnswer")
        }

        return lang.t("question.submit")
    }

    private func submitAnswer() {
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
        selections[question.question] ?? []
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
        "\(question.question)|\(option.label)"
    }

    private func optionKey(for question: QuestionPromptItem, option: QuestionOption) -> String {
        "\(question.question)|\(option.label)"
    }

    private func optionFillColor(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return V6Palette.paper.opacity(0.10)
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
        var selected = selections[question.question] ?? []

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
        selections[question.question] = selected
    }
}
