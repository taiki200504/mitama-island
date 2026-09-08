import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Focus timer presets")
struct FocusTimerPresetTests {
    @Test("Every preset carries a distinct localization key")
    func labelKeysAreDistinct() {
        let keys = Set(FocusTimerPreset.allCases.map(\.labelKey))
        #expect(keys.count == FocusTimerPreset.allCases.count)
    }

    @Test("Pomodoro and eye break map to their named modes")
    func namedPresetsMapToNamedModes() {
        guard case .pomodoro = FocusTimerPreset.pomodoro.mode else {
            Issue.record("expected .pomodoro mode")
            return
        }
        guard case .eyeBreak = FocusTimerPreset.eyeBreak.mode else {
            Issue.record("expected .eyeBreak mode")
            return
        }
    }

    @Test("The fixed-minute presets map to a plain countdown of that length")
    func minutePresetsMapToCountdown() {
        let expectations: [(FocusTimerPreset, TimeInterval)] = [
            (.five, 5 * 60),
            (.ten, 10 * 60),
            (.fifteen, 15 * 60),
            (.twentyFive, 25 * 60),
        ]
        for (preset, seconds) in expectations {
            guard case .countdown(let duration) = preset.mode else {
                Issue.record("expected .countdown mode for \(preset)")
                continue
            }
            #expect(duration == seconds)
        }
    }

    @Test("Preset ids match their raw values, for a stable ForEach identity")
    func idsMatchRawValues() {
        for preset in FocusTimerPreset.allCases {
            #expect(preset.id == preset.rawValue)
        }
    }
}
