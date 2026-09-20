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

    /// The reference's own beats: 1.4 / 3.5 / 5.0 / 5.8 / 8.0 / 9.8 / 10.8 /
    /// 12.5 / 13.8 / 16.6 / 18.4 — dark, white, tunnel, white-out, interface,
    /// checks, language, sign-in, confirmation, welcome, dive, end.
    @Test("Phases follow the timeline in order")
    func phasesFollowTheTimeline() {
        #expect(LinkstartSequence.phase(at: 0.01) == .awakening)
        #expect(LinkstartSequence.phase(at: 1.39) == .awakening)
        #expect(LinkstartSequence.phase(at: 1.41) == .ignition)
        #expect(LinkstartSequence.phase(at: 3.49) == .ignition)
        #expect(LinkstartSequence.phase(at: 3.51) == .warp)
        #expect(LinkstartSequence.phase(at: 4.99) == .warp)
        #expect(LinkstartSequence.phase(at: 5.01) == .flash)
        #expect(LinkstartSequence.phase(at: 5.79) == .flash)
        if case .calibration = LinkstartSequence.phase(at: 5.81) {
            // Expected.
        } else {
            Issue.record("Expected .calibration at 5.81, got \(LinkstartSequence.phase(at: 5.81))")
        }
        #expect(LinkstartSequence.phase(at: 7.99) != .sensesCheck)
        // The reference's own beats, to two decimal places.
        #expect(LinkstartSequence.phase(at: 0.5) == .awakening)
        #expect(LinkstartSequence.phase(at: 2.0) == .ignition)
        #expect(LinkstartSequence.phase(at: 4.0) == .warp)
        #expect(LinkstartSequence.phase(at: 5.4) == .flash)
        #expect(LinkstartSequence.phase(at: 9.0) == .sensesCheck)
        #expect(LinkstartSequence.phase(at: 10.2) == .languageSelect)
        #expect(LinkstartSequence.phase(at: 11.6) == .loginPanel)
        #expect(LinkstartSequence.phase(at: 13.0) == .confirmationDialog)
        #expect(LinkstartSequence.phase(at: 15.0) == .welcome)
        #expect(LinkstartSequence.phase(at: 17.4) == .dive)
        #expect(LinkstartSequence.phase(at: 18.7) == .fade)
        #expect(LinkstartSequence.phase(at: LinkstartSequence.duration + 0.01) == .complete)
    }

    @Test("The senses confirm one at a time, in order")
    func sensesConfirmOneByOne() {
        let start = LinkstartSequence.calibrationStart
        let step = LinkstartSequence.calibrationDuration / Double(LinkstartSequence.senses.count)
        var previous = LinkstartSequence.confirmedSenseCount(at: start)
        for index in 0..<LinkstartSequence.senses.count {
            let count = LinkstartSequence.confirmedSenseCount(at: start + step * (Double(index) + 0.5))
            #expect(count >= previous)
            previous = count
        }
        // By the time the checks appear, every sense is lit.
        #expect(LinkstartSequence.confirmedSenseCount(at: LinkstartSequence.sensesCheckStart + 0.01)
            == LinkstartSequence.senses.count)
    }

    @Test("The screens after the interface follow in the reference's order")
    func laterPhasesFollowInOrder() {
        #expect(LinkstartSequence.phase(at: LinkstartSequence.sensesCheckStart + 0.1) == .sensesCheck)
        #expect(LinkstartSequence.phase(at: LinkstartSequence.languageSelectStart + 0.1) == .languageSelect)
        #expect(LinkstartSequence.phase(at: LinkstartSequence.loginPanelStart + 0.1) == .loginPanel)
        #expect(LinkstartSequence.phase(at: LinkstartSequence.confirmationDialogStart + 0.1) == .confirmationDialog)
        #expect(LinkstartSequence.phase(at: LinkstartSequence.welcomeStart + 0.1) == .welcome)
        #expect(LinkstartSequence.phase(at: LinkstartSequence.diveStart + 0.1) == .dive)
        #expect(LinkstartSequence.phase(at: LinkstartSequence.duration + 0.01) == .complete)
    }

    /// The whole point of the new timings: an installed soundtrack runs
    /// straight through, so the picture's own length has to match the
    /// recording it was measured from.
    @Test("The sequence runs as long as the recording it follows")
    func totalLengthMatchesTheReference() {
        #expect(abs(LinkstartSequence.duration - 19.04) < 0.01)
        #expect(abs(LinkstartSequence.warpStart - 3.5) < 0.01)
        #expect(abs(LinkstartSequence.calibrationStart - 5.8) < 0.01)
        #expect(abs(LinkstartSequence.sensesCheckStart - 8.1) < 0.01)
        #expect(abs(LinkstartSequence.languageSelectStart - 9.5) < 0.01)
        #expect(abs(LinkstartSequence.loginPanelStart - 10.4) < 0.01)
        #expect(abs(LinkstartSequence.confirmationDialogStart - 12.0) < 0.01)
        #expect(abs(LinkstartSequence.welcomeStart - 13.6) < 0.01)
        #expect(abs(LinkstartSequence.diveStart - 16.6) < 0.01)
    }

    /// The checklist is on screen the whole way through, so it needs a full
    /// count long after the checks themselves are over.
    @Test("Every sense stays lit once the checks are done")
    func sensesStayLit() {
        let sensesEnd = LinkstartSequence.sensesCheckStart
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

        // rise, warp, flash, one tick per sense, resolve, dive.
        #expect(schedule.count == LinkstartSequence.senses.count + 5)
        #expect(schedule.prefix(3).map(\.cue) == [.rise, .warp, .flash])
        #expect(schedule.prefix(3).map(\.at) == [0, LinkstartSequence.warpStart, LinkstartSequence.flashStart])

        // One tick per sense, spread across the calibration, ending as the
        // checks appear.
        let ticks = schedule.filter { $0.cue == .tick }
        #expect(ticks.count == LinkstartSequence.senses.count)
        #expect(ticks.first?.at ?? 0 > LinkstartSequence.calibrationStart)
        #expect(abs((ticks.last?.at ?? 0) - LinkstartSequence.sensesCheckStart) < 1e-9)

        // Resolve as the interface settles, then the dive closes the sequence.
        #expect(schedule.contains { $0.cue == .resolve && abs($0.at - LinkstartSequence.sensesCheckStart) < 1e-9 })
        #expect(schedule.last?.cue == .dive)
        #expect(abs((schedule.last?.at ?? 0) - LinkstartSequence.diveStart) < 1e-9)
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

        let middleOfTheDive = LinkstartSequence.warpStart + LinkstartSequence.warpDuration / 2
        let mid = LinkstartSequence.streaks(at: middleOfTheDive)
        #expect(mid.count == LinkstartSequence.streakCount)
        #expect(mid == LinkstartSequence.streaks(at: middleOfTheDive))
        for streak in mid {
            #expect(streak.inner <= streak.outer)
            #expect(streak.outer <= 1.15)
            #expect((0...1).contains(streak.hue))
            #expect((0...1).contains(streak.opacity))
        }
        // Actually moving: a later moment is a different frame.
        #expect(LinkstartSequence.streaks(at: LinkstartSequence.warpStart + 0.2)
            != LinkstartSequence.streaks(at: LinkstartSequence.warpStart + 1.2))
        // Not all piled up in one place.
        #expect(Set(mid.map { Int($0.angle * 10) }).count > 40)
    }

    @Test("The dive speeds up and the core brightens with it")
    func warpAccelerates() {
        let early = LinkstartSequence.warpStart + 0.2
        let late = LinkstartSequence.warpStart + LinkstartSequence.warpDuration * 0.9
        #expect(LinkstartSequence.warpSpeed(at: early) < LinkstartSequence.warpSpeed(at: late))
        #expect(LinkstartSequence.coreGlow(at: early) < LinkstartSequence.coreGlow(at: late))
        #expect(LinkstartSequence.coreGlow(at: 0.2) == 0)
    }

    @Test("One white-out, peaking at the tunnel's end and gone by calibration")
    func flashIsSingleAndCapped() {
        #expect(LinkstartSequence.flashOpacity(at: LinkstartSequence.warpStart) == 0)
        // Peaks where the tunnel ends and the white-out begins.
        #expect(abs(LinkstartSequence.flashOpacity(at: LinkstartSequence.flashStart) - LinkstartSequence.flashPeakOpacity) < 1e-9)
        #expect(LinkstartSequence.flashOpacity(at: LinkstartSequence.calibrationStart) == 0)

        // Rises once, falls once: never a second peak.
        var rising = true
        var previous = 0.0
        for elapsed in stride(from: LinkstartSequence.warpStart, through: LinkstartSequence.calibrationStart, by: 0.01) {
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
        // Gone by the time the tunnel is running.
        #expect(LinkstartSequence.titleSlam(at: LinkstartSequence.warpStart + 1.1).opacity == 0)
    }

    @Test("Sync rate climbs from 0 to 100 and never goes back")
    func syncRateClimbs() {
        #expect(LinkstartSequence.syncRate(at: LinkstartSequence.calibrationStart) == 0)
        #expect(LinkstartSequence.syncRate(at: LinkstartSequence.sensesCheckStart) == 100)
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
        // The wash runs through the calibration window, wherever that sits.
        let calibration = LinkstartSequence.calibrationStart
        func steps(_ elapsed: TimeInterval) -> [CalibrationStep] {
            LinkstartSequence.calibrationFrames(at: elapsed).map(\.step)
        }
        func opacity(_ elapsed: TimeInterval, _ step: CalibrationStep) -> Double? {
            LinkstartSequence.calibrationFrames(at: elapsed).first { $0.step == step }?.opacity
        }

        #expect(steps(calibration + 0.0) == [.red])
        #expect(opacity(calibration + 0.0, .red) == 0.35)
        #expect(steps(calibration + 0.2) == [.red])
        #expect(steps(calibration + 0.45) == [.green])
        #expect(steps(calibration + 0.75) == [.blue])
        #expect(steps(calibration + 0.97) == [.white])

        let redGreen = LinkstartSequence.calibrationFrames(at: calibration + 0.30)
        #expect(Set(redGreen.map(\.step)) == [.red, .green])
        #expect(redGreen.allSatisfy { abs($0.opacity - 0.175) < 0.01 })

        #expect(Set(LinkstartSequence.calibrationFrames(at: calibration + 0.60).map(\.step)) == [.green, .blue])
        #expect(Set(LinkstartSequence.calibrationFrames(at: calibration + 0.90).map(\.step)) == [.blue, .white])

        #expect(opacity(calibration + 0.26, .red)! > opacity(calibration + 0.26, .green) ?? 0)
        #expect(opacity(calibration + 0.34, .green)! > opacity(calibration + 0.34, .red) ?? 0)

        #expect(steps(calibration + -0.01).isEmpty)
        #expect(steps(LinkstartSequence.sensesCheckStart + 0.01).isEmpty)
    }

    @Test("Fade opacity runs from 1 to 0 across the closing window")
    func fadeOpacityRunsToZero() {
        #expect(LinkstartSequence.fadeOpacity(at: 0) == 1)
        #expect(LinkstartSequence.fadeOpacity(at: LinkstartSequence.fadeStart) == 1)
        #expect(LinkstartSequence.fadeOpacity(at: LinkstartSequence.duration) == 0)
        #expect(LinkstartSequence.fadeOpacity(at: LinkstartSequence.duration + 10) == 0)
    }
}
