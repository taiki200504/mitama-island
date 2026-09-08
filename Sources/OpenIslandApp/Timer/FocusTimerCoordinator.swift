import AppKit
import Foundation
import Observation
import OpenIslandCore

/// Owns the one focus timer the app runs: a countdown, a Pomodoro, or the
/// 20-20-20 eye break. `FocusTimerReducer` decides every state transition;
/// this only supplies the wall clock — sleeping until a phase is due,
/// recomputing after the machine wakes, and carrying out what a finished
/// phase means for sound and the closed-island sneak peek.
@MainActor
@Observable
final class FocusTimerCoordinator {
    private(set) var state: FocusTimerState = .idle

    @ObservationIgnored var soundSettings: SoundSettings = .init()
    @ObservationIgnored var timerSettings: TimerSettings = .init()
    @ObservationIgnored var lang: LanguageManager = .shared
    /// Weak: the coordinator outlives no overlay, but nothing about a timer
    /// finishing should keep the overlay coordinator alive past its own
    /// owner.
    @ObservationIgnored weak var overlay: OverlayUICoordinator?

    @ObservationIgnored private var runLoopTask: Task<Void, Never>?
    @ObservationIgnored private var restCountdownTask: Task<Void, Never>?
    /// Never removed: the coordinator is app-lifetime (owned by `AppModel`,
    /// never torn down while the app runs), and a `deinit` that touches this
    /// token is rejected under strict concurrency — see the note below.
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    init() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.recomputeAfterWake()
            }
        }
    }

    // No deinit: the coordinator lives as long as the app (owned by AppModel),
    // and touching the observer token from a nonisolated deinit is rejected
    // under strict concurrency. The block observer is removed by the process.

    // MARK: - Controls

    func start(_ mode: FocusTimerMode) {
        cancelTasks()
        state = FocusTimerReducer.reduce(state, .start(mode), now: .now)
        scheduleRunLoop()
    }

    func pause() {
        state = FocusTimerReducer.reduce(state, .pause, now: .now)
        cancelTasks()
    }

    func resume() {
        state = FocusTimerReducer.reduce(state, .resume, now: .now)
        scheduleRunLoop()
    }

    func reset() {
        cancelTasks()
        state = FocusTimerReducer.reduce(state, .reset, now: .now)
    }

    /// Sets the state directly, with no run loop attached — how a harness
    /// scenario poses the timer for a screenshot without a real countdown
    /// running underneath it.
    func loadDebugState(_ debugState: FocusTimerState) {
        cancelTasks()
        state = debugState
    }

    /// Moves a `.finished` phase into whatever comes next — the opened
    /// surface's own controls call this when `autoAdvance` is off, so it has
    /// to do the same follow-through `handlePhaseFinished()` does once a
    /// phase advances on its own: re-arm the run loop for the phase that
    /// just started, and if that phase is an eye-break rest, start narrating
    /// it live. Skipping either would leave a manually-advanced rest
    /// silently ticking with no countdown shown.
    func advance() {
        guard case .finished = state.phase else { return }
        state = FocusTimerReducer.reduce(state, .advance, now: .now)
        scheduleRunLoop()
        startEyeBreakRestCountdownIfNeeded()
    }

    private func cancelTasks() {
        runLoopTask?.cancel()
        runLoopTask = nil
        restCountdownTask?.cancel()
        restCountdownTask = nil
    }

    // MARK: - Run loop

    /// A macOS sleep is wall-clock time the process never sees pass — the
    /// sleeping `Task` below only fires once the machine wakes anyway, but a
    /// long enough nap can wake up past a phase's `endsAt` with the timer
    /// still reporting itself `.running`. Re-checking here is what turns
    /// that into a same-tick `.finished`.
    private func recomputeAfterWake() {
        guard case .running = state.phase else { return }
        applyTick(now: .now)
    }

    private func scheduleRunLoop() {
        runLoopTask?.cancel()
        guard case .running(let endsAt) = state.phase else { return }

        runLoopTask = Task { [weak self] in
            let interval = max(0, endsAt.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            self?.applyTick(now: .now)
        }
    }

    private func applyTick(now: Date) {
        guard case .running = state.phase else { return }
        let next = FocusTimerReducer.reduce(state, .tick, now: now)
        guard next != state else {
            // Woke early (a wake notification racing the scheduled sleep) —
            // nothing finished yet, so just re-arm for the real deadline.
            scheduleRunLoop()
            return
        }
        state = next
        handlePhaseFinished()
    }

    private func handlePhaseFinished() {
        playFinishSound()
        presentFinishSneakPeek()

        guard timerSettings.autoAdvance else { return }
        advance()
    }

    private func playFinishSound() {
        guard timerSettings.playsSound else { return }
        NotificationSoundService.play(.timerFinished, settings: soundSettings)
    }

    /// Announces the phase that just ended. Read before `.advance` runs, so
    /// `state.isRest` still describes the phase that finished rather than
    /// the one about to start.
    private func presentFinishSneakPeek() {
        let text: String
        switch state.mode {
        case .countdown:
            text = lang.t("timer.sneakPeek.done")
        case .pomodoro, .eyeBreak:
            text = state.isRest ? lang.t("timer.sneakPeek.done") : lang.t("timer.sneakPeek.breakTime")
        }
        overlay?.presentSneakPeek(
            IslandSneakPeek(kind: .timerDone, text: text, icon: "timer", until: .now.addingTimeInterval(4))
        )
    }

    /// The one phase short enough to narrate live: a 20-second eye-break rest
    /// re-offers the same `timerDone` kind every second with an updated
    /// count — `IslandSneakPeekPolicy` lets an equal kind always replace what
    /// it's showing, so this reads as one countdown rather than a new
    /// interruption each time.
    private func startEyeBreakRestCountdownIfNeeded() {
        guard case .eyeBreak = state.mode, state.isRest, case .running = state.phase else { return }

        restCountdownTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                guard case .running = self.state.phase, self.state.isRest,
                      case .eyeBreak = self.state.mode else { return }
                let seconds = Int(self.state.remaining(at: .now).rounded(.up))
                guard seconds > 0 else { return }
                self.overlay?.presentSneakPeek(
                    IslandSneakPeek(
                        kind: .timerDone,
                        text: self.lang.t("timer.sneakPeek.restSeconds", seconds),
                        icon: "eye",
                        until: .now.addingTimeInterval(1.3)
                    )
                )
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
