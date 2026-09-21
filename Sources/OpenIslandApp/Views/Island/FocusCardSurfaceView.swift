import SwiftUI
import OpenIslandCore

/// The opened `.focusCard` surface: where you left off, and the one next step
/// you wrote down for yourself on the way out.
///
/// Deliberately not a list of everything you have ever interrupted. The card
/// you are holding gets the room; what came before it is a short tail you can
/// reach back into, and nothing more. A resume screen that needs reading is a
/// second interruption.
struct FocusCardSurfaceView: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }
    private var state: FocusCardState { model.focusCard }

    /// How far back the tail goes. Three is what fits without the surface
    /// growing a scroller, and further back than three the card has stopped
    /// being "where I was" and become a diary.
    private static let historyLimit = 3

    var body: some View {
        VStack(spacing: 10) {
            Text(lang.t("focusCard.title"))
                .saoCaps(size: 13, text: lang.t("focusCard.title"))
                .foregroundStyle(V6Palette.paper.opacity(0.55))
                .padding(.top, 4)

            if let current = state.currentCard {
                currentCardView(current)
            } else {
                emptyState
            }

            if !state.history.isEmpty {
                historyTail
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Current

    private func currentCardView(_ card: ResumeCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title)
                .font(.islandText(size: 13, weight: .semibold))
                .foregroundStyle(V6Palette.paper)
                .lineLimit(2)

            if !card.nextAction.isEmpty {
                Text(card.nextAction)
                    .font(.islandText(size: 11.5))
                    .foregroundStyle(V6Palette.paper.opacity(0.7))
                    .lineLimit(2)
            }

            Text(elapsedText(card.savedAt))
                .font(.islandMono(size: 10.5))
                .foregroundStyle(V6Palette.paper.opacity(0.45))

            HStack(spacing: 8) {
                Button(lang.t("focusCard.dismiss")) {
                    Task { await model.dismissCurrentCard() }
                }
                .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true, surface: .darkShell))

                Button(lang.t("focusCard.resume")) {
                    Task {
                        await model.resumeFromCard(card)
                        model.notchClose()
                    }
                }
                .buttonStyle(IslandActionButtonStyle(kind: .primary, expands: true, surface: .darkShell))
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(V6Palette.paper.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text(lang.t("focusCard.empty"))
                .font(.islandText(size: 12))
                .foregroundStyle(V6Palette.paper.opacity(0.55))
            // The only place the key is ever taught. It has no menu item and
            // no setting, so if it is not said here it is said nowhere.
            Text(lang.t("focusCard.hint", FocusCardTrigger.displayLabel))
                .font(.islandMono(size: 10.5))
                .foregroundStyle(V6Palette.paper.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    // MARK: - Elapsed

    /// The coarse unit comes from `FocusCardElapsed` so it can be checked at
    /// exact ages; only the wording is decided here.
    private func elapsedText(_ savedAt: Date) -> String {
        switch FocusCardElapsed.unit(since: savedAt) {
        case .justNow:          lang.t("focusCard.elapsed.justNow")
        case let .minutes(n):   lang.t("focusCard.elapsed.minutes", n)
        case let .hours(n):     lang.t("focusCard.elapsed.hours", n)
        case let .days(n):      lang.t("focusCard.elapsed.days", n)
        }
    }

    // MARK: - History

    private var historyTail: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lang.t("focusCard.history"))
                .saoCaps(size: 10.5, text: lang.t("focusCard.history"))
                .foregroundStyle(V6Palette.paper.opacity(0.4))

            ForEach(state.history.prefix(Self.historyLimit), id: \.id) { card in
                Button {
                    Task {
                        await model.resumeFromCard(card)
                        model.notchClose()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(card.title)
                            .font(.islandText(size: 11.5))
                            .foregroundStyle(V6Palette.paper.opacity(0.8))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(elapsedText(card.savedAt))
                            .font(.islandMono(size: 10))
                            .foregroundStyle(V6Palette.paper.opacity(0.4))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
