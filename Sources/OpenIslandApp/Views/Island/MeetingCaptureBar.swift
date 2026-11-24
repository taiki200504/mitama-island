import AppKit
import OpenIslandCore
import SwiftUI

/// The opened island's row for meeting capture: 録音中 with stop / discard while
/// recording, "notes are being made" after hand-off, and the summary once
/// mitama-os writes `summary.json`. Styled like the current-event bar above it.
struct MeetingCaptureBar: View {
    let capture: MeetingCaptureCoordinator
    private var lang: LanguageManager { LanguageManager.shared }

    var body: some View {
        switch capture.phase {
        case .idle:
            EmptyView()
        case let .recording(_, title, startedAt):
            recording(title: title, startedAt: startedAt)
        case let .processing(_, title, _):
            processing(title: title)
        case let .summaryReady(_, title, summary):
            summaryCard(title: title, summary: summary)
        }
    }

    private func recording(title: String, startedAt: Date) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .shadow(color: Color.red.opacity(0.7), radius: 4)
            Text(lang.t("meeting.recording"))
                .font(.islandMono(size: 11, weight: .semibold))
                .foregroundStyle(Color.red)
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                Text(MeetingCapturePhase.elapsedText(from: startedAt, to: context.date))
                    .font(.islandMono(size: 11))
                    .foregroundStyle(V6Palette.paper.opacity(0.7))
            }
            Text(title)
                .font(.islandText(size: 12, weight: .medium))
                .foregroundStyle(V6Palette.paper.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            pillButton(lang.t("meeting.stop"), systemImage: "stop.fill", tint: SAOGrammar.Palette.accentOrange) {
                capture.stopRecording()
            }
            pillButton(lang.t("meeting.discard"), systemImage: "trash", tint: V6Palette.paper.opacity(0.12), foreground: V6Palette.paper.opacity(0.85)) {
                capture.discardRecording()
            }
        }
        .modifier(MeetingBarBackground(stroke: Color.red.opacity(0.35)))
    }

    private func processing(title: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .scaleEffect(0.6)
                .frame(width: 12, height: 12)
            Text(lang.t("meeting.processing"))
                .font(.islandText(size: 12, weight: .medium))
                .foregroundStyle(V6Palette.paper.opacity(0.9))
            Text(title)
                .font(.islandText(size: 12))
                .foregroundStyle(V6Palette.paper.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .modifier(MeetingBarBackground(stroke: V6Palette.paper.opacity(0.15)))
    }

    private func summaryCard(title: String, summary: MeetingSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.islandText(size: 11, weight: .semibold))
                    .foregroundStyle(SAOGrammar.Palette.accentOrange)
                Text(title)
                    .font(.islandText(size: 12, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.95))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if !summary.countsLine.isEmpty {
                    Text(summary.countsLine)
                        .font(.islandMono(size: 10))
                        .foregroundStyle(V6Palette.paper.opacity(0.6))
                }
            }
            Text(summary.summary)
                .font(.islandText(size: 12))
                .foregroundStyle(V6Palette.paper.opacity(0.85))
                .lineLimit(6)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(summary.decisions.prefix(3).enumerated()), id: \.offset) { _, decision in
                Text("・" + decision)
                    .font(.islandText(size: 11))
                    .foregroundStyle(V6Palette.paper.opacity(0.75))
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if let hub = summary.hubURL, let url = URL(string: hub), url.scheme == "https" {
                    pillButton(lang.t("meeting.openHub"), systemImage: "arrow.up.right", tint: SAOGrammar.Palette.accentOrange) {
                        NSWorkspace.shared.open(url)
                    }
                }
                pillButton(lang.t("meeting.dismiss"), systemImage: "xmark", tint: V6Palette.paper.opacity(0.12), foreground: V6Palette.paper.opacity(0.85)) {
                    capture.dismissSummary()
                }
            }
        }
        .modifier(MeetingBarBackground(stroke: SAOGrammar.Palette.accentOrange.opacity(0.30)))
    }

    private func pillButton(
        _ title: String,
        systemImage: String,
        tint: Color,
        foreground: Color = V6Palette.ink,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.islandMono(size: 10, weight: .semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tint, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct MeetingBarBackground: ViewModifier {
    let stroke: Color

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                IslandThemes.current.shape(cornerRadius: 10)
                    .fill(V6Palette.paper.opacity(0.07))
                    .overlay(
                        IslandThemes.current.shape(cornerRadius: 10)
                            .stroke(stroke, lineWidth: 0.5)
                    )
            )
    }
}
