import Foundation

/// What the timer is counting toward. A plain countdown ends once; a
/// Pomodoro or an eye-break cycle through work and rest indefinitely, which
/// is why they carry their own phase lengths rather than being expressed as
/// a sequence of countdowns strung together.
public enum FocusTimerMode: Equatable, Sendable {
    case countdown(TimeInterval)
    /// `every` counts work sessions, not phases: after the 4th work session
    /// finishes, the rest that follows is `long` instead of `short`.
    case pomodoro(work: TimeInterval = 25 * 60, short: TimeInterval = 5 * 60, long: TimeInterval = 15 * 60, every: Int = 4)
    case eyeBreak(work: TimeInterval = 20 * 60, rest: TimeInterval = 20)
}

/// Where the current phase stands. `endsAt`/`remaining` are wall-clock
/// values rather than a stored elapsed duration, so a paused timer survives
/// the app not running without drifting, and a running one needs no ticking
/// state of its own between checks.
public enum FocusTimerPhase: Equatable, Sendable {
    case idle
    case running(endsAt: Date)
    case paused(remaining: TimeInterval)
    /// The active phase reached zero at `at`. Distinct from `.idle` so a
    /// caller can tell "never started" from "just finished" and decide
    /// whether to advance into the next phase or stop.
    case finished(at: Date)
}

/// One action the timer can be asked to take. `tick` and `advance` are kept
/// separate: a coordinator calls `tick` on every clock check (which is a
/// no-op unless the phase's end has actually passed) and `advance` only once
/// it — or the person watching it — decides to move on to the next phase.
public enum FocusTimerAction: Sendable {
    case start(FocusTimerMode)
    case pause
    case resume
    case reset
    case tick
    case advance
}

/// A focus timer's full state: what it's counting toward, where the current
/// phase stands, and enough about that phase (`cycle`, `isRest`) to know
/// what comes next.
public struct FocusTimerState: Equatable, Sendable {
    public let mode: FocusTimerMode
    public let phase: FocusTimerPhase
    /// How many work sessions have finished. Only meaningful for `.pomodoro`
    /// (it decides when the long rest lands) and `.eyeBreak` (only used for
    /// display, e.g. a cycle count).
    public let cycle: Int
    /// Whether the current (or just-finished) phase is a rest, not work.
    /// Always `false` for `.countdown`, which has no rest phase.
    public let isRest: Bool
    /// The full length of the current (or just-finished) phase — kept
    /// alongside `phase` rather than re-derived from `mode`, so
    /// `progress(at:)` doesn't have to re-run the same phase-length logic
    /// `FocusTimerReducer` already worked out when the phase started.
    public let currentPhaseDuration: TimeInterval

    public init(mode: FocusTimerMode, phase: FocusTimerPhase, cycle: Int, isRest: Bool, currentPhaseDuration: TimeInterval) {
        self.mode = mode
        self.phase = phase
        self.cycle = cycle
        self.isRest = isRest
        self.currentPhaseDuration = currentPhaseDuration
    }

    public static let idle = FocusTimerState(mode: .countdown(0), phase: .idle, cycle: 0, isRest: false, currentPhaseDuration: 0)

    /// What the closed-island accessory (or any other minutes-only readout)
    /// shows, or `nil` while idle or finished — a timer that has nothing left
    /// to count down has nothing to report until it advances.
    public struct Snapshot: Equatable, Sendable {
        public let remainingMinutes: Int
        public let label: String
        public let isRest: Bool
    }

    public func snapshot(at now: Date) -> Snapshot? {
        switch phase {
        case .idle, .finished:
            return nil
        case .running, .paused:
            // Rounded up, not to the nearest minute: a background pill that
            // re-ticked every second to show seconds would redraw sixty times
            // a minute, and showing "0" with 40 seconds still on the clock
            // would read as done when it isn't.
            let minutes = max(0, Int((remaining(at: now) / 60).rounded(.up)))
            return Snapshot(remainingMinutes: minutes, label: displayLabel, isRest: isRest)
        }
    }

    /// Seconds left in the current phase, clamped to zero. Never negative
    /// even if the wall clock jumped backwards underneath a running phase.
    public func remaining(at now: Date) -> TimeInterval {
        switch phase {
        case .idle, .finished:
            return 0
        case .running(let endsAt):
            return max(0, endsAt.timeIntervalSince(now))
        case .paused(let remaining):
            return max(0, remaining)
        }
    }

    /// How far through the current phase the clock is, 0...1. Also clamped
    /// against a backwards clock: `remaining(at:)` can never exceed
    /// `currentPhaseDuration` in that case without this pulling it back in.
    public func progress(at now: Date) -> Double {
        guard currentPhaseDuration > 0 else {
            switch phase {
            case .idle: return 0
            default: return 1
            }
        }
        let elapsed = currentPhaseDuration - remaining(at: now)
        return min(max(elapsed / currentPhaseDuration, 0), 1)
    }

    private var displayLabel: String {
        switch mode {
        case .countdown:
            "FOCUS"
        case .pomodoro, .eyeBreak:
            isRest ? "REST" : "WORK"
        }
    }
}

/// Turns an action into the next state. Pure: every branch reads only its
/// arguments, so a coordinator can call this from a sleeping `Task` without
/// worrying about drift — the state carries wall-clock `Date`s, not counters
/// that need a steady tick to stay right.
public enum FocusTimerReducer {
    public static func reduce(_ state: FocusTimerState, _ action: FocusTimerAction, now: Date) -> FocusTimerState {
        switch action {
        case .start(let mode):
            return start(mode: mode, now: now)
        case .pause:
            guard case .running(let endsAt) = state.phase else { return state }
            return FocusTimerState(
                mode: state.mode,
                phase: .paused(remaining: max(0, endsAt.timeIntervalSince(now))),
                cycle: state.cycle,
                isRest: state.isRest,
                currentPhaseDuration: state.currentPhaseDuration
            )
        case .resume:
            guard case .paused(let remaining) = state.phase else { return state }
            return FocusTimerState(
                mode: state.mode,
                phase: .running(endsAt: now.addingTimeInterval(remaining)),
                cycle: state.cycle,
                isRest: state.isRest,
                currentPhaseDuration: state.currentPhaseDuration
            )
        case .reset:
            return .idle
        case .tick:
            guard case .running(let endsAt) = state.phase, now >= endsAt else { return state }
            return FocusTimerState(
                mode: state.mode,
                phase: .finished(at: endsAt),
                cycle: state.cycle,
                isRest: state.isRest,
                currentPhaseDuration: state.currentPhaseDuration
            )
        case .advance:
            guard case .finished = state.phase else { return state }
            return advance(from: state, now: now)
        }
    }

    private static func start(mode: FocusTimerMode, now: Date) -> FocusTimerState {
        let duration = firstPhaseDuration(for: mode)
        return FocusTimerState(
            mode: mode,
            phase: .running(endsAt: now.addingTimeInterval(duration)),
            cycle: 0,
            isRest: false,
            currentPhaseDuration: duration
        )
    }

    private static func firstPhaseDuration(for mode: FocusTimerMode) -> TimeInterval {
        switch mode {
        case .countdown(let duration): max(0, duration)
        case .pomodoro(let work, _, _, _): work
        case .eyeBreak(let work, _): work
        }
    }

    private static func advance(from state: FocusTimerState, now: Date) -> FocusTimerState {
        switch state.mode {
        case .countdown:
            // Nothing left to advance to — a single countdown ends by going
            // idle rather than looping.
            return .idle

        case .pomodoro(let work, let short, let long, let every):
            if state.isRest {
                return FocusTimerState(
                    mode: state.mode,
                    phase: .running(endsAt: now.addingTimeInterval(work)),
                    cycle: state.cycle,
                    isRest: false,
                    currentPhaseDuration: work
                )
            }
            let cycle = state.cycle + 1
            let isLongRest = every > 0 && cycle.isMultiple(of: every)
            let duration = isLongRest ? long : short
            return FocusTimerState(
                mode: state.mode,
                phase: .running(endsAt: now.addingTimeInterval(duration)),
                cycle: cycle,
                isRest: true,
                currentPhaseDuration: duration
            )

        case .eyeBreak(let work, let rest):
            if state.isRest {
                return FocusTimerState(
                    mode: state.mode,
                    phase: .running(endsAt: now.addingTimeInterval(work)),
                    cycle: state.cycle,
                    isRest: false,
                    currentPhaseDuration: work
                )
            }
            return FocusTimerState(
                mode: state.mode,
                phase: .running(endsAt: now.addingTimeInterval(rest)),
                cycle: state.cycle + 1,
                isRest: true,
                currentPhaseDuration: rest
            )
        }
    }
}

/// A one-tap starting point for the timer — the menu bar and the opened
/// surface both offer this fixed set rather than a free-form duration
/// picker.
public enum FocusTimerPreset: String, CaseIterable, Identifiable, Sendable {
    case pomodoro
    case eyeBreak
    case five
    case ten
    case fifteen
    case twentyFive

    public var id: String { rawValue }

    public var mode: FocusTimerMode {
        switch self {
        case .pomodoro: .pomodoro()
        case .eyeBreak: .eyeBreak()
        case .five: .countdown(5 * 60)
        case .ten: .countdown(10 * 60)
        case .fifteen: .countdown(15 * 60)
        case .twentyFive: .countdown(25 * 60)
        }
    }

    public var labelKey: String { "timer.preset.\(rawValue)" }
}
