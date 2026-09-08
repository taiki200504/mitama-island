import OpenIslandCore
import SwiftUI

/// The idle screen: a clock, what is next, and who is waiting.
///
/// Laid out the way Aerial puts information over a moving background — a large
/// centre and quiet corners — but with the wallpaper left where it is instead
/// of a video on top of it. The video was the part that needed a download
/// pipeline and a cache; the layer discipline is the part worth having.
struct AmbientBoardView: View {
    let board: AmbientBoard
    let nextEvent: UpcomingCalendarEvent.Band?
    let currentEvent: UpcomingCalendarEvent.Current?
    /// Captured once at presentation; the row below recomputes its own
    /// readout from this against the board's own once-a-second clock, the
    /// same way `nextEventRow` does from `event.startsAt`.
    var timer: FocusTimerState = .idle
    /// `(title, artist)`, captured once at presentation like `timer` above.
    var nowPlaying: (title: String, artist: String?)?
    let lang: LanguageManager

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let reducesMotion = IslandMotion.reducesMotion

            ZStack {
                // Dark enough to read white type over any wallpaper, light
                // enough that the desktop is still visibly there — this is the
                // machine resting, not the machine off.
                V6Palette.ink.opacity(0.88)
                    .ignoresSafeArea()

                // A faint pulse behind the clock, echoing the login sequence's
                // own rings — the same shared grammar, at rest.
                SAORingView(progress: 1, count: 2, tint: V6Palette.paper)
                    .opacity(0.06)
                    .rotationEffect(reducesMotion ? .zero : Self.ringRotation(at: context.date))
                    .allowsHitTesting(false)

                VStack(spacing: 26) {
                    Spacer(minLength: 0)

                    FlipClockView(date: context.date)

                    Text(Self.dateText(context.date, lang: lang))
                        .font(.islandMono(size: 14, weight: .medium))
                        .foregroundStyle(V6Palette.paper.opacity(0.40))
                        .textCase(.uppercase)
                        .kerning(2.4)

                    // A meeting already in progress outranks "what's next" —
                    // there's nothing next about it any more.
                    if let currentEvent {
                        currentEventRow(currentEvent)
                            .padding(.top, 8)
                    } else if let nextEvent {
                        nextEventRow(nextEvent, now: context.date)
                            .padding(.top, 8)
                    }

                    if let snapshot = timer.snapshot(at: context.date) {
                        timerRow(snapshot)
                            .padding(.top, 8)
                    }

                    if let nowPlaying {
                        nowPlayingRow(nowPlaying)
                            .padding(.top, 8)
                    }

                    Spacer(minLength: 0)

                    if !board.isQuiet {
                        waitingPanel
                            .padding(.bottom, 8)
                    }

                    Text(lang.t("ambient.dismiss"))
                        .font(.islandText(size: 11))
                        .foregroundStyle(V6Palette.paper.opacity(0.26))
                        .padding(.bottom, 34)
                }
                .padding(.horizontal, 48)
            }
        }
    }

    // MARK: - What is next

    @ViewBuilder
    private func nextEventRow(_ event: UpcomingCalendarEvent.Band, now: Date) -> some View {
        // Recomputed against the live clock rather than trusting the minutes
        // captured when the board opened: this screen stays up for hours.
        let minutes = max(0, Int(ceil(event.startsAt.timeIntervalSince(now) / 60)))

        HStack(spacing: 12) {
            Circle()
                .fill(IslandThemes.current.statusTints.running)
                .frame(width: 7, height: 7)

            Text(Self.clock.string(from: event.startsAt))
                .font(.islandMono(size: 20, weight: .semibold))
                .foregroundStyle(V6Palette.paper.opacity(0.88))

            Text(event.title)
                .font(.islandText(size: 15))
                .foregroundStyle(V6Palette.paper.opacity(0.66))
                .lineLimit(1)
                .truncationMode(.tail)

            Text(lang.t("island.peek.inMinutes", minutes))
                .font(.islandMono(size: 14, weight: .medium))
                .foregroundStyle(IslandThemes.current.statusTints.running.opacity(0.9))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(V6Palette.paper.opacity(0.05), in: Capsule())
    }

    /// A meeting already in progress: "NOW · title · until HH:MM" rather than
    /// a countdown to something that already started.
    @ViewBuilder
    private func currentEventRow(_ event: UpcomingCalendarEvent.Current) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(SAOGrammar.Palette.accentOrange)
                .frame(width: 7, height: 7)

            Text(lang.t("ambient.now"))
                .font(.islandMono(size: 20, weight: .semibold))
                .foregroundStyle(V6Palette.paper.opacity(0.88))

            Text(event.title)
                .font(.islandText(size: 15))
                .foregroundStyle(V6Palette.paper.opacity(0.66))
                .lineLimit(1)
                .truncationMode(.tail)

            Text(lang.t("ambient.until", Self.clock.string(from: event.endsAt)))
                .font(.islandMono(size: 14, weight: .medium))
                .foregroundStyle(SAOGrammar.Palette.accentOrange.opacity(0.9))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(V6Palette.paper.opacity(0.05), in: Capsule())
    }

    // MARK: - Focus timer

    private func timerRow(_ snapshot: FocusTimerState.Snapshot) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(SAOGrammar.Palette.accentOrange)
                .frame(width: 7, height: 7)

            Text(snapshot.label)
                .font(.islandMono(size: 14, weight: .semibold))
                .foregroundStyle(V6Palette.paper.opacity(0.72))

            Text(lang.t("island.peek.inMinutes", snapshot.remainingMinutes))
                .font(.islandMono(size: 14, weight: .medium))
                .foregroundStyle(SAOGrammar.Palette.accentOrange.opacity(0.9))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(V6Palette.paper.opacity(0.05), in: Capsule())
    }

    // MARK: - Now playing

    private func nowPlayingRow(_ track: (title: String, artist: String?)) -> some View {
        let text = track.artist.map { "\(track.title) — \($0)" } ?? track.title
        return HStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.islandText(size: 12, weight: .semibold))
                .foregroundStyle(V6Palette.paper.opacity(0.55))

            Text(text)
                .font(.islandMono(size: 13, weight: .medium))
                .foregroundStyle(V6Palette.paper.opacity(0.72))
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(V6Palette.paper.opacity(0.05), in: Capsule())
    }

    // MARK: - Who is waiting

    private var waitingPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lang.t("ambient.waiting"))
                .font(.islandMono(size: 10, weight: .semibold))
                .foregroundStyle(V6Palette.paper.opacity(0.34))
                .kerning(1.8)
                .textCase(.uppercase)

            ForEach(Array(board.alerts.enumerated()), id: \.offset) { _, title in
                row(
                    tint: IslandThemes.current.statusTints.critical,
                    label: IslandPeekBand.mitamaLabel,
                    detail: title
                )
            }

            ForEach(Array(board.waiting.enumerated()), id: \.offset) { _, waiting in
                row(
                    tint: IslandThemes.current.statusTints.waitingForApproval,
                    label: waiting.agent,
                    detail: elapsedText(waiting.elapsed)
                )
            }

            if board.hiddenCount > 0 {
                Text(lang.t("ambient.more", board.hiddenCount))
                    .font(.islandMono(size: 11))
                    .foregroundStyle(V6Palette.paper.opacity(0.34))
                    .padding(.leading, 19)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .frame(maxWidth: 560, alignment: .leading)
        .background(Self.waitingPanelShape.fill(V6Palette.paper.opacity(0.045)))
        .clipShape(Self.waitingPanelShape)
        .saoOutline(Self.waitingPanelShape, scale: 1.0)
    }

    private static let waitingPanelShape = SAOPanelShape(
        cornerRadius: 6,
        cuts: [.topTrailing, .bottomLeading],
        cutDepth: 12
    )

    /// One full turn per minute, driven by the board's own once-a-second
    /// clock rather than a separate animation — a decoration this quiet
    /// doesn't need its own timer.
    private static func ringRotation(at date: Date) -> Angle {
        let seconds = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60)
        return .degrees(seconds / 60 * 360)
    }

    private func row(tint: Color, label: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .shadow(color: tint.opacity(0.8), radius: IslandThemes.current.glowRadius)

            Text(label)
                .font(.islandMono(size: 13, weight: .semibold))
                .foregroundStyle(V6Palette.paper.opacity(0.86))
                .frame(width: 78, alignment: .leading)

            Text(detail)
                .font(.islandText(size: 13))
                .foregroundStyle(V6Palette.paper.opacity(0.62))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func elapsedText(_ elapsed: IslandPeekBand.Elapsed) -> String {
        switch elapsed {
        case .justNow: lang.t("island.peek.justNow")
        case .minutes(let minutes): lang.t("island.peek.minutes", minutes)
        case .hours(let hours): lang.t("island.peek.hours", hours)
        }
    }

    // MARK: - Formatters

    private static func dateText(_ date: Date, lang: LanguageManager) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: lang.language.resolvedCode)
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter.string(from: date)
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
