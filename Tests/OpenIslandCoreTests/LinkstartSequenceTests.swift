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

    /// 0 / 0.5 / 3.0 / 3.5 / 4.5 / 7.0 / 7.9 / 9.7 / 10.5 — ignition, warp,
    /// flash, calibration, senses, language, identity, fade, complete.
    @Test("Phases follow the timeline in order")
    func phasesFollowTheTimeline() {
        #expect(LinkstartSequence.phase(at: 0.01) == .ignition)
        #expect(LinkstartSequence.phase(at: 0.49) == .ignition)
        #expect(LinkstartSequence.phase(at: 0.51) == .warp)
        #expect(LinkstartSequence.phase(at: 2.99) == .warp)
        #expect(LinkstartSequence.phase(at: 3.01) == .flash)
        #expect(LinkstartSequence.phase(at: 3.49) == .flash)
        if case .calibration = LinkstartSequence.phase(at: 3.51) {
            // Expected.
        } else {
            Issue.record("Expected .calibration at 3.51, got \(LinkstartSequence.phase(at: 3.51))")
        }
        #expect(LinkstartSequence.phase(at: 4.51) == .senses(checked: 0))
        #expect(LinkstartSequence.phase(at: 6.99) == .senses(checked: 4))
        #expect(LinkstartSequence.phase(at: 7.01) == .language)
        #expect(LinkstartSequence.phase(at: 7.89) == .language)
        #expect(LinkstartSequence.phase(at: 7.91) == .identity)
        #expect(LinkstartSequence.phase(at: 9.69) == .identity)
        #expect(LinkstartSequence.phase(at: 9.71) == .fade)
        #expect(LinkstartSequence.phase(at: 10.49) == .fade)
        #expect(LinkstartSequence.phase(at: 10.51) == .complete)
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

    /// Rise, warp, flash, one tick per sense, resolve — each landing exactly
    /// where the thing it announces begins.
    @Test("The cue schedule follows rise, warp, flash, one tick per sense, then resolve")
    func cueScheduleMatchesThePhases() {
        let schedule = LinkstartSequence.cueSchedule

        #expect(schedule.count == LinkstartSequence.senses.count + 4)
        #expect(schedule.prefix(3).map(\.cue) == [.rise, .warp, .flash])
        #expect(schedule.prefix(3).map(\.at) == [0, LinkstartSequence.warpStart, LinkstartSequence.warpEnd])

        let ticks = schedule.filter { $0.cue == .tick }
        let expectedTickTimes: [TimeInterval] = [4.5, 5.0, 5.5, 6.0, 6.5]
        #expect(zip(ticks.map(\.at), expectedTickTimes).allSatisfy { abs($0 - $1) < 1e-9 })

        #expect(schedule.last?.cue == .resolve)
        #expect(schedule.last?.at == LinkstartSequence.identityStart)
        #expect(schedule.map(\.at) == schedule.map(\.at).sorted())
    }

    // MARK: - Ignition, warp, flash, calibration, fade

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

    @Test("The tunnel only exists during the dive, and is the same frame every time")
    func tunnelIsBoundedAndDeterministic() {
        #expect(LinkstartSequence.streaks(at: 0.2).isEmpty)
        #expect(LinkstartSequence.streaks(at: LinkstartSequence.warpEnd).isEmpty)

        let mid = LinkstartSequence.streaks(at: 1.7)
        #expect(mid.count == LinkstartSequence.streakCount)
        #expect(mid == LinkstartSequence.streaks(at: 1.7))
        for streak in mid {
            #expect(streak.inner <= streak.outer)
            #expect(streak.outer <= 1.15)
            #expect((0...1).contains(streak.hue))
            #expect((0...1).contains(streak.opacity))
        }
        // Actually moving: a later moment is a different frame.
        #expect(LinkstartSequence.streaks(at: 1.0) != LinkstartSequence.streaks(at: 2.0))
        // Not all piled up in one place.
        #expect(Set(mid.map { Int($0.angle * 10) }).count > 40)
    }

    @Test("The dive speeds up and the core brightens with it")
    func warpAccelerates() {
        #expect(LinkstartSequence.warpSpeed(at: 1.0) < LinkstartSequence.warpSpeed(at: 2.5))
        #expect(LinkstartSequence.coreGlow(at: 1.0) < LinkstartSequence.coreGlow(at: 2.9))
        #expect(LinkstartSequence.coreGlow(at: 0.2) == 0)
    }

    @Test("One white-out, peaking at the tunnel's end and gone by calibration")
    func flashIsSingleAndCapped() {
        #expect(LinkstartSequence.flashOpacity(at: 2.0) == 0)
        #expect(abs(LinkstartSequence.flashOpacity(at: LinkstartSequence.warpEnd) - LinkstartSequence.flashPeakOpacity) < 1e-9)
        #expect(LinkstartSequence.flashOpacity(at: LinkstartSequence.calibrationStart) == 0)

        // Rises once, falls once: never a second peak.
        var rising = true
        var previous = 0.0
        for elapsed in stride(from: 2.5, through: 4.0, by: 0.01) {
            let value = LinkstartSequence.flashOpacity(at: elapsed)
            #expect(value <= LinkstartSequence.flashPeakOpacity + 1e-9)
            if value < previous - 1e-9 { rising = false }
            if !rising { #expect(value <= previous + 1e-9) }
            previous = value
        }
    }

    @Test("The title slams in, then is gone before the white-out")
    func titleSlamsInThenLeaves() {
        #expect(LinkstartSequence.titleSlam(at: 0).opacity == 0)
        let landed = LinkstartSequence.titleSlam(at: 0.5)
        #expect(abs(landed.scale - 1) < 0.01)
        #expect(landed.opacity == 1)
        #expect(LinkstartSequence.titleSlam(at: 2.0).opacity == 0)
    }

    @Test("Sync rate climbs from 0 to 100 and never goes back")
    func syncRateClimbs() {
        #expect(LinkstartSequence.syncRate(at: LinkstartSequence.calibrationStart) == 0)
        #expect(LinkstartSequence.syncRate(at: LinkstartSequence.identityStart) == 100)
        var previous = 0
        for elapsed in stride(from: 0.0, through: LinkstartSequence.duration, by: 0.05) {
            let rate = LinkstartSequence.syncRate(at: elapsed)
            #expect(rate >= previous)
            previous = rate
        }
    }

    /// Red holds 3.50–3.75, crossfades to green over 3.75–3.85, green holds
    /// to 4.05, to blue over 4.05–4.15, blue holds to 4.35, to white over
    /// 4.35–4.45, white holds to 4.50 — once, and nothing outside [3.50, 4.50).
    @Test("Calibration washes red, green, blue, then white, crossfading between them")
    func calibrationWashesColorsOnce() {
        func steps(_ elapsed: TimeInterval) -> [CalibrationStep] {
            LinkstartSequence.calibrationFrames(at: elapsed).map(\.step)
        }
        func opacity(_ elapsed: TimeInterval, _ step: CalibrationStep) -> Double? {
            LinkstartSequence.calibrationFrames(at: elapsed).first { $0.step == step }?.opacity
        }

        #expect(steps(3.50) == [.red])
        #expect(opacity(3.50, .red) == 0.35)
        #expect(steps(3.70) == [.red])
        #expect(steps(3.95) == [.green])
        #expect(steps(4.25) == [.blue])
        #expect(steps(4.47) == [.white])

        let redGreen = LinkstartSequence.calibrationFrames(at: 3.80)
        #expect(Set(redGreen.map(\.step)) == [.red, .green])
        #expect(redGreen.allSatisfy { abs($0.opacity - 0.175) < 0.01 })

        #expect(Set(LinkstartSequence.calibrationFrames(at: 4.10).map(\.step)) == [.green, .blue])
        #expect(Set(LinkstartSequence.calibrationFrames(at: 4.40).map(\.step)) == [.blue, .white])

        #expect(opacity(3.76, .red)! > opacity(3.76, .green) ?? 0)
        #expect(opacity(3.84, .green)! > opacity(3.84, .red) ?? 0)

        #expect(steps(3.49).isEmpty)
        #expect(steps(4.50).isEmpty)
    }

    @Test("Fade opacity runs from 1 to 0 across the closing window")
    func fadeOpacityRunsToZero() {
        #expect(LinkstartSequence.fadeOpacity(at: 0) == 1)
        #expect(LinkstartSequence.fadeOpacity(at: LinkstartSequence.fadeStart) == 1)
        #expect(LinkstartSequence.fadeOpacity(at: LinkstartSequence.duration) == 0)
        #expect(LinkstartSequence.fadeOpacity(at: LinkstartSequence.duration + 10) == 0)
    }
}
