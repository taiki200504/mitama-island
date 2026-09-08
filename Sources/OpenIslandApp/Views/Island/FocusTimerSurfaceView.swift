import SwiftUI
import OpenIslandCore

/// The opened `.timer` surface: a countdown ring, the flip-clock digits, a
/// preset row and the transport controls. Only this view refreshes on a
/// 1-second clock — the closed-island accessory and the menu bar both read
/// `FocusTimerState` on demand instead of ticking.
struct FocusTimerSurfaceView: View {
    var model: AppModel

    private var timer: FocusTimerCoordinator { model.focusTimer }
    private var lang: LanguageManager { model.lang }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let state = timer.state

        VStack(spacing: 14) {
            Text(headerTitle(for: state))
                .saoCaps(size: 13)
                .foregroundStyle(V6Palette.paper.opacity(0.55))
                .padding(.top, 4)

            ZStack {
                SAORingView(
                    progress: state.progress(at: now),
                    count: 3,
                    tint: SAOGrammar.Palette.accentOrange
                )
                .frame(width: 148, height: 148)
                .opacity(state.phase == .idle ? 0.25 : 0.9)

                FlipClockView(digits: clockDigits(for: state, at: now), cardHeight: 46)
            }
            .frame(height: 148)

            if case .pomodoro(_, _, _, let every) = state.mode, every > 0 {
                cycleDots(for: state, every: every)
            }

            presetRow

            controlsRow(for: state)
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Header + digits

    private func headerTitle(for state: FocusTimerState) -> String {
        switch state.phase {
        case .idle:
            lang.t("timer.title.idle")
        default:
            state.isRest ? lang.t("timer.title.rest") : lang.t("timer.title.work")
        }
    }

    private func clockDigits(for state: FocusTimerState, at now: Date) -> String {
        let remaining = Int(state.remaining(at: now).rounded(.up))
        return String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }

    // MARK: - Pomodoro cycle dots

    private func cycleDots(for state: FocusTimerState, every: Int) -> some View {
        // Which of the current set of `every` work sessions have completed.
        // Right after the 4th one, `cycle` is already a multiple of `every`
        // — shown as a full set during that long rest (the set that just
        // finished is still worth seeing lit), then back to zero once the
        // next work session actually starts.
        let normalized = state.cycle % every
        let completed = normalized == 0 && state.cycle > 0 && state.isRest ? every : normalized
        return HStack(spacing: 6) {
            ForEach(0..<every, id: \.self) { index in
                Circle()
                    .fill(index < completed ? SAOGrammar.Palette.accentOrange : V6Palette.paper.opacity(0.16))
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - Presets

    private var presetChipShape: SAOPanelShape {
        SAOPanelShape(cornerRadius: SAOGrammar.Metric.cornerRadius, cutDepth: 8)
    }

    private var presetRow: some View {
        HStack(spacing: 8) {
            ForEach(FocusTimerPreset.allCases) { preset in
                Button {
                    timer.start(preset.mode)
                } label: {
                    Text(lang.t(preset.labelKey))
                        .font(.islandText(size: 10.5, weight: .semibold))
                        .foregroundStyle(V6Palette.paper.opacity(0.82))
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(presetChipShape.fill(V6Palette.paper.opacity(0.07)))
                        .overlay(presetChipShape.stroke(V6Palette.paper.opacity(0.14), lineWidth: 1))
                        .clipShape(presetChipShape)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Transport

    private func controlsRow(for state: FocusTimerState) -> some View {
        HStack(spacing: 10) {
            Button(action: { primaryAction(for: state) }) {
                Text(primaryActionLabel(for: state))
            }
            .buttonStyle(IslandActionButtonStyle(kind: .primary, expands: true, surface: .darkShell))

            if state.phase != .idle {
                Button(action: { timer.reset() }) {
                    Text(lang.t("timer.action.reset"))
                }
                .buttonStyle(IslandActionButtonStyle(kind: .secondary, surface: .darkShell))
            }
        }
    }

    private func primaryActionLabel(for state: FocusTimerState) -> String {
        switch state.phase {
        case .idle, .finished:
            lang.t("timer.action.start")
        case .running:
            lang.t("timer.action.pause")
        case .paused:
            lang.t("timer.action.resume")
        }
    }

    private func primaryAction(for state: FocusTimerState) {
        switch state.phase {
        case .idle:
            timer.start(.pomodoro())
        case .finished:
            switch state.mode {
            case .countdown:
                // Nothing to advance to — restart the same duration.
                timer.start(state.mode)
            case .pomodoro, .eyeBreak:
                // Move into the next phase rather than restarting the cycle
                // from scratch, which would drop the cycle count `start`
                // always resets to zero.
                timer.advance()
            }
        case .running:
            timer.pause()
        case .paused:
            timer.resume()
        }
    }
}
