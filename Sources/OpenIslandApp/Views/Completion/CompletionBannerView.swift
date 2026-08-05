import SwiftUI

/// What one completion banner says.
struct CompletionBannerContent: Equatable, Sendable {
    var sessionID: String
    /// The workspace or session name. Never a prompt — this is on screen for
    /// everyone in the room to read, including during a screen share.
    var title: String
    var agentName: String
    /// How long the session ran, already formatted for reading.
    var duration: String?
}

/// Whether the banner is arriving, sitting, or being handed off to the island.
///
/// Shared with the controller so the exit can be played before the window goes
/// away. Without it, clicking the banner made it vanish and a different panel
/// appear in its place — two unrelated events for what is one movement.
@MainActor
@Observable
final class CompletionBannerPhase {
    var isLeaving = false
}

/// The "it's done" announcement, shown just under the notch.
///
/// The words stay plain — "完了", a name, a duration. Everything that makes this
/// feel like a heads-up display is in the shape, the light and the motion, not
/// in the vocabulary.
struct CompletionBannerView: View {
    let content: CompletionBannerContent
    /// Opens the island on this session. The banner says *that* it finished;
    /// the panel behind this says what it did.
    var onOpen: (() -> Void)?
    /// Dismisses the banner early. Also told when the pointer arrives so the
    /// countdown can be held — see `CompletionBannerController`.
    var onClose: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    /// Fixed rather than measured. `fittingSize` on a hosting view forces a
    /// layout pass before the view is in a window, and the panel has to be
    /// positioned relative to the notch before it can be shown anyway.
    static let size = CGSize(width: 320, height: 56)

    /// Owned by the controller, which flips `isLeaving` before the window is
    /// ordered out.
    var phase: CompletionBannerPhase = CompletionBannerPhase()

    @State private var isRevealed = false
    @State private var isHovering = false

    private var theme: any IslandTheme { IslandThemes.current }
    private var accent: Color { theme.statusTints.completed }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(accent)
                .shadow(color: accent.opacity(0.9), radius: theme.glowRadius * 1.5)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(LanguageManager.shared.t("banner.completed"))
                    .font(.islandText(size: 14, weight: .bold))
                    .foregroundStyle(theme.paper)

                Text(subtitle)
                    .font(.islandMono(size: 10.5, weight: .medium))
                    .foregroundStyle(theme.paper.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            // Only shown once there is somewhere to go, so the banner never
            // implies a summary it cannot open.
            if onOpen != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.paper.opacity(isHovering ? 0.7 : 0.3))
                    .accessibilityHidden(true)
            }

            closeButton
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 9)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(theme.shape(cornerRadius: 11).fill(theme.ink.opacity(0.96)))
        .overlay(theme.shape(cornerRadius: 11).strokeBorder(accent.opacity(0.5), lineWidth: 1))
        .overlay(alignment: .top) { sweepLine }
        .shadow(color: accent.opacity(0.25), radius: 14)
        .shadow(color: .black.opacity(0.45), radius: 18, y: 6)
        .clipShape(theme.shape(cornerRadius: 11))
        // Slides down out of the notch on arrival and back up into it on the
        // way out, so opening the summary reads as one movement rather than one
        // thing disappearing and another appearing.
        .offset(y: phase.isLeaving ? -22 : (isRevealed ? 0 : -10))
        .opacity(phase.isLeaving ? 0 : (isRevealed ? 1 : 0))
        .scaleEffect(phase.isLeaving ? 0.94 : 1, anchor: .top)
        .animation(.easeIn(duration: CompletionBannerPhase.exitDuration), value: phase.isLeaving)
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { isRevealed = true }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
            onHoverChanged?(hovering)
        }
        // The close button sits on top of this and stops the tap itself, so
        // dismissing never also opens the panel.
        .contentShape(Rectangle())
        .onTapGesture { onOpen?() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(LanguageManager.shared.t("banner.completed")) \(content.title)")
        .accessibilityHint(onOpen == nil ? "" : LanguageManager.shared.t("banner.openHint"))
    }

    /// Hidden until the pointer arrives. A permanent close button on something
    /// that goes away by itself is one more piece of furniture to look past.
    private var closeButton: some View {
        Button {
            onClose?()
        } label: {
            // The label carries the hit area; the surrounding tap opens the
            // panel, so this has to swallow its own click.
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(theme.paper.opacity(0.75))
                .frame(width: 18, height: 18)
                .background(Circle().fill(.white.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isHovering ? 1 : 0)
        // Not just invisible — unclickable too, so the spot it occupies stays
        // inert while the banner is only being read.
        .allowsHitTesting(isHovering)
        .accessibilityLabel(LanguageManager.shared.t("banner.dismiss"))
    }

    /// A hairline along the top edge, lit from the middle. Ties the banner to
    /// the island it fell out of.
    private var sweepLine: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, accent, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1.5)
            .scaleEffect(x: isRevealed ? 1 : 0.2)
            .shadow(color: accent.opacity(0.8), radius: theme.glowRadius * 2)
    }

    /// Name and duration only.
    ///
    /// The agent's name was here too and pushed the duration off the end at this
    /// width. Between "which agent" and "how long did that take", the second is
    /// the one you cannot get from anywhere else at this moment.
    private var subtitle: String {
        [content.title, content.duration]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "  ·  ")
    }
}


extension CompletionBannerPhase {
    /// Long enough to read as movement, short enough that the panel it hands off
    /// to is not left waiting.
    static let exitDuration: TimeInterval = 0.18
}
