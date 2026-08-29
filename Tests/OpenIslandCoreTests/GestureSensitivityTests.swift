import Foundation
import Testing
@testable import OpenIslandCore

@Suite struct GestureSensitivityTests {
    @Test func unknownValuesReadAsTheMiddleSetting() {
        #expect(GestureSensitivity(rawValue: "low") == .low)
        #expect(GestureSensitivity(rawValue: "high") == .high)
        #expect(GestureSensitivity(rawValue: "medium") == .medium)
        // A downgrade or a hand-edited plist must not leave the camera with no
        // configuration at all.
        #expect(GestureSensitivity(rawValue: "ludicrous") == .medium)
        #expect(GestureSensitivity(rawValue: "") == .medium)
    }

    @Test func lowerSensitivityAsksForALongerHold() {
        #expect(GestureSensitivity.low.palmHold.minimumHoldDuration
            > GestureSensitivity.medium.palmHold.minimumHoldDuration)
        #expect(GestureSensitivity.medium.palmHold.minimumHoldDuration
            > GestureSensitivity.high.palmHold.minimumHoldDuration)
    }

    /// The cooldown has to move with the hold. A hand is usually still up when
    /// the gesture fires, so a cooldown shorter than the hold fires a second
    /// time off the same raised hand.
    @Test func everyLevelCoolsDownForLongerThanItHolds() {
        for level in GestureSensitivity.allCases {
            #expect(level.palmHold.cooldownDuration > level.palmHold.minimumHoldDuration)
        }
    }

    @Test func mediumIsUnchangedFromWhatTheDetectorsShippedWith() {
        let shipped = PoseHoldDetector.Configuration()
        #expect(GestureSensitivity.medium.palmHold == shipped)
        #expect(GestureSensitivity.default == .medium)
    }

    /// The hold is what the setting is for: at `low` a palm held for the
    /// medium duration must not fire, and at `high` it must.
    @Test func theSameHoldLandsDifferentlyAtEachLevel() {
        func fires(at level: GestureSensitivity, holdingFor seconds: TimeInterval) -> Bool {
            var detector = PoseHoldDetector(configuration: level.palmHold)
            _ = detector.push(isPosed: true, timestamp: 0)
            return detector.push(isPosed: true, timestamp: seconds)
        }

        #expect(fires(at: .low, holdingFor: 0.6) == false)
        #expect(fires(at: .medium, holdingFor: 0.6))
        #expect(fires(at: .high, holdingFor: 0.6))
        #expect(fires(at: .high, holdingFor: 0.4))
        #expect(fires(at: .medium, holdingFor: 0.4) == false)
    }
}
