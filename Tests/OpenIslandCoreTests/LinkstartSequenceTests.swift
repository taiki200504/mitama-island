import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Linkstart sequence")
struct LinkstartSequenceTests {
    @Test("It starts in the light, with nothing checked")
    func startsAwakening() {
        #expect(LinkstartSequence.phase(at: 0) == .awakening)
        #expect(LinkstartSequence.confirmedSenseCount(at: 0.5) == 0)
    }

    /// A clock that jumps backwards must not put the sequence in a state the
    /// view has no drawing for.
    @Test("Time before the beginning is still the beginning")
    func negativeTimeIsAwakening() {
        #expect(LinkstartSequence.phase(at: -5) == .awakening)
    }

    /// 0 / 1.2 / 2.0 / 3.0 / 5.5 / 6.4 / 8.0 / 8.8 — rings, rays, calibration,
    /// senses, language, identity, fade, complete.
    @Test("Phases follow the timeline in order")
    func phasesFollowTheTimeline() {
        #expect(LinkstartSequence.phase(at: 0.01) == .rings)
        #expect(LinkstartSequence.phase(at: 1.19) == .rings)
        #expect(LinkstartSequence.phase(at: 1.21) == .rays)
        #expect(LinkstartSequence.phase(at: 1.99) == .rays)
        if case .calibration = LinkstartSequence.phase(at: 2.01) {
            // Expected.
        } else {
            Issue.record("Expected .calibration at 2.01, got \(LinkstartSequence.phase(at: 2.01))")
        }
        if case .calibration = LinkstartSequence.phase(at: 2.99) {
            // Expected.
        } else {
            Issue.record("Expected .calibration at 2.99, got \(LinkstartSequence.phase(at: 2.99))")
        }
        #expect(LinkstartSequence.phase(at: 3.01) == .senses(checked: 0))
        #expect(LinkstartSequence.phase(at: 5.49) == .senses(checked: 4))
        #expect(LinkstartSequence.phase(at: 5.51) == .language)
        #expect(LinkstartSequence.phase(at: 6.39) == .language)
        #expect(LinkstartSequence.phase(at: 6.41) == .identity)
        #expect(LinkstartSequence.phase(at: 7.99) == .identity)
        #expect(LinkstartSequence.phase(at: 8.01) == .fade)
        #expect(LinkstartSequence.phase(at: 8.79) == .fade)
        #expect(LinkstartSequence.phase(at: 8.81) == .complete)
    }

    @Test("The senses confirm one at a time, in order")
    func sensesConfirmOneByOne() {
        let start = LinkstartSequence.sensesStart
        #expect(LinkstartSequence.phase(at: start + 0.01) == .senses(checked: 0))
        #expect(LinkstartSequence.phase(at: start + 0.6) == .senses(checked: 1))
        #expect(LinkstartSequence.phase(at: start + 1.1) == .senses(checked: 2))
        #expect(LinkstartSequence.phase(at: start + 2.4) == .senses(checked: 4))
    }

    @Test("Language and identity follow the senses, then it ends")
    func laterPhasesFollowInOrder() {
        #expect(LinkstartSequence.phase(at: LinkstartSequence.languageStart + 0.1) == .language)
        #expect(LinkstartSequence.phase(at: LinkstartSequence.identityStart + 0.1) == .identity)
        #expect(LinkstartSequence.phase(at: LinkstartSequence.duration + 0.01) == .complete)
    }

    /// The checklist is on screen the whole way through, so it needs a full
    /// count long after the checks themselves are over.
    @Test("Every sense stays lit once the checks are done")
    func sensesStayLit() {
        let sensesEnd = LinkstartSequence.sensesStart + LinkstartSequence.sensesDuration
        #expect(LinkstartSequence.confirmedSenseCount(at: sensesEnd) == LinkstartSequence.senses.count)
        #expect(LinkstartSequence.confirmedSenseCount(at: 60) == LinkstartSequence.senses.count)
    }

    @Test("The count never runs past the list")
    func countIsBounded() {
        for elapsed in stride(from: 0.0, through: LinkstartSequence.duration + 2, by: 0.05) {
            let count = LinkstartSequence.confirmedSenseCount(at: elapsed)
            #expect(count >= 0)
            #expect(count <= LinkstartSequence.senses.count)
        }
    }

    @Test("Every sense carries a distinct string key")
    func senseKeysAreDistinct() {
        let keys = Set(LinkstartSequence.senses.map(\.labelKey))
        #expect(keys.count == LinkstartSequence.senses.count)
    }

    /// One rise, one tick per sense, one resolve — and each lands exactly
    /// where the phase it announces begins, so the sound and the checklist
    /// can never drift apart. Times: 0 / 3.0 / 3.5 / 4.0 / 4.5 / 5.0 / 6.4.
    @Test("The cue schedule follows the rise, one tick per sense, then resolve")
    func cueScheduleMatchesThePhases() {
        let schedule = LinkstartSequence.cueSchedule

        #expect(schedule.count == LinkstartSequence.senses.count + 2)
        #expect(schedule.first?.at == 0)
        #expect(schedule.first?.cue == .rise)

        let ticks = schedule.filter { $0.cue == .tick }
        let expectedTickTimes: [TimeInterval] = [3.0, 3.5, 4.0, 4.5, 5.0]
        #expect(ticks.map(\.at) == expectedTickTimes)

        #expect(schedule.last?.cue == .resolve)
        #expect(schedule.last?.at == 6.4)
    }

    // MARK: - Rings, rays, calibration, fade

    @Test("Ring progress is monotonic in time and each ring lags the one before it")
    func ringProgressIsMonotonicWithLag() {
        let early = LinkstartSequence.ringProgress(at: 0.3)
        let late = LinkstartSequence.ringProgress(at: 1.2)
        #expect(early.count == 5)
        #expect(late.count == 5)
        for index in early.indices {
            #expect(late[index] >= early[index])
        }
        // At any moment, a later ring is never further along than an earlier one.
        for index in 1..<late.count {
            #expect(late[index] <= late[index - 1])
        }
        #expect(LinkstartSequence.ringProgress(at: LinkstartSequence.ringsDuration)[0] == 1)
    }

    @Test("Ray progress runs from 0 to 1 across its own window")
    func rayProgressRunsItsWindow() {
        #expect(LinkstartSequence.rayProgress(at: LinkstartSequence.raysStart) == 0)
        #expect(LinkstartSequence.rayProgress(at: LinkstartSequence.raysEnd) == 1)
        #expect(LinkstartSequence.rayProgress(at: 0) == 0)
    }

    /// Red holds 2.00–2.25, crossfades to green over 2.25–2.35, green holds
    /// to 2.55, crossfades to blue over 2.55–2.65, blue holds to 2.85,
    /// crossfades to white over 2.85–2.95, white holds to 3.00 — once, not a
    /// repeating cycle, and nothing outside [2.00, 3.00).
    @Test("Calibration washes red, green, blue, then white, crossfading between them")
    func calibrationWashesColorsOnce() {
        func steps(_ elapsed: TimeInterval) -> [CalibrationStep] {
            LinkstartSequence.calibrationFrames(at: elapsed).map(\.step)
        }
        func opacity(_ elapsed: TimeInterval, _ step: CalibrationStep) -> Double? {
            LinkstartSequence.calibrationFrames(at: elapsed).first { $0.step == step }?.opacity
        }

        // Pure holds: exactly one frame, at the wash's one and only strength.
        #expect(steps(2.00) == [.red])
        #expect(opacity(2.00, .red) == 0.35)
        #expect(steps(2.20) == [.red])
        #expect(steps(2.45) == [.green])
        #expect(steps(2.75) == [.blue])
        #expect(steps(2.97) == [.white])

        // Crossfades: two frames, opposite ends of the same 0.35 strength.
        let redGreen = LinkstartSequence.calibrationFrames(at: 2.30)
        #expect(Set(redGreen.map(\.step)) == [.red, .green])
        #expect(redGreen.allSatisfy { abs($0.opacity - 0.175) < 0.01 })

        let greenBlue = LinkstartSequence.calibrationFrames(at: 2.60)
        #expect(Set(greenBlue.map(\.step)) == [.green, .blue])

        let blueWhite = LinkstartSequence.calibrationFrames(at: 2.90)
        #expect(Set(blueWhite.map(\.step)) == [.blue, .white])

        // No handoff runs faster than 0.30s apart — well under a strobe rate.
        #expect(opacity(2.26, .red)! > opacity(2.26, .green) ?? 0)
        #expect(opacity(2.34, .green)! > opacity(2.34, .red) ?? 0)

        // Nothing outside the wash, including its own tail and the moment
        // the senses begin.
        #expect(steps(1.99).isEmpty)
        #expect(steps(3.00).isEmpty)
    }

    @Test("Fade opacity runs from 1 to 0 across the closing window")
    func fadeOpacityRunsToZero() {
        #expect(LinkstartSequence.fadeOpacity(at: 0) == 1)
        #expect(LinkstartSequence.fadeOpacity(at: LinkstartSequence.fadeStart) == 1)
        #expect(LinkstartSequence.fadeOpacity(at: LinkstartSequence.duration) == 0)
        #expect(LinkstartSequence.fadeOpacity(at: LinkstartSequence.duration + 10) == 0)
    }
}
