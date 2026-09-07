import SwiftUI
@preconcurrency import MarkdownUI
import OpenIslandCore

extension IslandSessionRow {
    var completionActionBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !completionMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AutoHeightScrollView(maxHeight: 240) {
                    Markdown(completionMessageText)
                        .markdownTheme(.completionCard)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                }
            } else {
                completionEmptyState
            }

            if onReply != nil {
                Rectangle()
                    .fill(V6Palette.paper.opacity(completionDividerOpacity))
                    .frame(height: 1)

                completionReplyInput
            }
        }
        .background(
            IslandThemes.current.shape(cornerRadius: 10)
                .fill(V6Palette.paper.opacity(completionCardFillOpacity))
        )
        .overlay(
            IslandThemes.current.shape(cornerRadius: 10)
                .strokeBorder(V6Palette.paper.opacity(completionCardStrokeOpacity))
        )
    }

    private var completionDoneOpacity: Double {
        presentation == .notification ? 0.82 : 0.96
    }

    private var completionDividerOpacity: Double {
        presentation == .notification ? 0.035 : 0.04
    }

    private var completionCardFillOpacity: Double {
        presentation == .notification ? 0.035 : 0.045
    }

    private var completionCardStrokeOpacity: Double {
        presentation == .notification ? 0.06 : 0.08
    }

    private var completionEmptyState: some View {
        HStack {
            Text(lang.t("completion.done"))
                .font(.islandText(size: 11.5, weight: .bold))
                .foregroundStyle(IslandDesignPalette.Status.completed.opacity(completionDoneOpacity))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var completionReplyInput: some View {
        HStack(spacing: 8) {
            ReplyTextField(
                placeholder: lang.t("completion.replyPlaceholder", session.completionReplyRecipientName),
                text: $replyText,
                onSubmit: { submitReply() }
            )
            .frame(height: 32)

            Button {
                submitReply()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.islandText(size: 24))
                    .foregroundColor(replyText.trimmingCharacters(in: .whitespaces).isEmpty
                        ? V6Palette.paper.opacity(0.2) : V6Palette.paper.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(replyText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func submitReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        replyText = ""
        onReply?(text)
    }

    var completionMessageText: String {
        if let text = session.completionAssistantMessageText?.trimmedForNotificationCard, !text.isEmpty {
            return text
        }
        let summary = session.summary.trimmedForNotificationCard
        return summary == SessionPhase.completed.displayName ? "" : summary
    }

}

// MARK: - MarkdownUI Theme

extension MarkdownUI.Theme {
    @MainActor static let completionCard = Theme()
        .text {
            // Read at a glance from a metre away, on a dark panel, often while
            // the user is mid-thought in another window.
            ForegroundColor(V6Palette.paper.opacity(0.96))
            FontSize(14)
            FontWeight(.medium)
        }
        .link {
            ForegroundColor(IslandThemes.current.accent)
        }
        .strong {
            FontWeight(.bold)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(12.5)
            ForegroundColor(V6Palette.paper.opacity(0.88))
            BackgroundColor(V6Palette.paper.opacity(0.08))
        }
        .codeBlock { configuration in
            configuration.label
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(12.5)
                    ForegroundColor(V6Palette.paper.opacity(0.88))
                }
                .padding(10)
                .background(V6Palette.paper.opacity(0.08))
                .clipShape(IslandThemes.current.shape(cornerRadius: 6))
        }
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontSize(16)
                    FontWeight(.bold)
                    ForegroundColor(V6Palette.paper.opacity(0.88))
                }
                .markdownMargin(top: 8, bottom: 4)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontSize(15)
                    FontWeight(.bold)
                    ForegroundColor(V6Palette.paper.opacity(0.88))
                }
                .markdownMargin(top: 8, bottom: 4)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontSize(14)
                    FontWeight(.semibold)
                    ForegroundColor(V6Palette.paper.opacity(0.88))
                }
                .markdownMargin(top: 6, bottom: 2)
        }
        .blockquote { configuration in
            configuration.label
                .markdownTextStyle {
                    ForegroundColor(V6Palette.paper.opacity(0.6))
                    FontSize(13.5)
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(V6Palette.paper.opacity(0.2))
                        .frame(width: 3)
                }
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 2, bottom: 2)
        }
        .table { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownTableBorderStyle(.init(.allBorders, color: V6Palette.paper.opacity(0.15), strokeStyle: .init(lineWidth: 1)))
                .markdownTableBackgroundStyle(
                    .alternatingRows(V6Palette.paper.opacity(0.04), V6Palette.paper.opacity(0.08))
                )
                .markdownMargin(top: 4, bottom: 8)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .relativeLineSpacing(.em(0.25))
        }
}
