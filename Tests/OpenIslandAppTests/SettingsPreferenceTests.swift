import Foundation
import Observation
import Testing
@testable import OpenIslandApp

/// Every test runs against a throwaway suite so the developer's own defaults are
/// never touched.
private func makeStore(_ name: String = UUID().uuidString) -> (PreferenceStore, UserDefaults) {
    let suite = UserDefaults(suiteName: name)!
    suite.removePersistentDomain(forName: name)
    return (PreferenceStore(suite: suite), suite)
}

/// Observation callbacks fire off the calling isolation, so the counter needs to
/// be a reference the closure can safely bump.
private final class ChangeCounter: @unchecked Sendable {
    private(set) var count = 0
    func increment() { count += 1 }
}

struct PreferenceStoreTests {
    @Test
    func returnsDeclaredDefaultWhenNothingStored() {
        let (store, _) = makeStore()
        #expect(store.value("absent.bool", default: true) == true)
        #expect(store.value("absent.int", default: 7) == 7)
        #expect(store.value("absent.double", default: 1.5) == 1.5)
        #expect(store.value("absent.string", default: "fallback") == "fallback")
        #expect(store.value("absent.strings", default: ["a"]) == ["a"])
    }

    @Test
    func roundTripsEveryRepresentableType() {
        let (store, _) = makeStore()

        store.setValue(false, forKey: "k.bool")
        store.setValue(42, forKey: "k.int")
        store.setValue(0.25, forKey: "k.double")
        store.setValue("hello", forKey: "k.string")
        store.setValue(["x", "y"], forKey: "k.strings")

        #expect(store.value("k.bool", default: true) == false)
        #expect(store.value("k.int", default: 0) == 42)
        #expect(store.value("k.double", default: 0) == 0.25)
        #expect(store.value("k.string", default: "") == "hello")
        #expect(store.value("k.strings", default: []) == ["x", "y"])
    }

    @Test
    func roundTripsStringBackedEnums() {
        let (store, _) = makeStore()
        store.setValue(IdleSessionCleanup.eightHours, forKey: "k.enum")
        #expect(store.value("k.enum", default: IdleSessionCleanup.never) == .eightHours)
    }

    /// A value written by an older build that no longer maps to a case must fall
    /// back rather than crash or resurrect a removed behaviour.
    @Test
    func unknownEnumRawValueFallsBackToDefault() {
        let (store, suite) = makeStore()
        suite.set("someRemovedCase", forKey: "k.enum")
        #expect(store.value("k.enum", default: IdleSessionCleanup.twoHours) == .twoHours)
    }

    @Test
    func typeMismatchFallsBackToDefault() {
        let (store, suite) = makeStore()
        suite.set("not a number", forKey: "k.double")
        #expect(store.value("k.double", default: 3.0) == 3.0)
    }

    @Test
    func removingAValueRestoresTheDefault() {
        let (store, _) = makeStore()
        store.setValue(99, forKey: "k.int")
        #expect(store.hasValue(forKey: "k.int"))
        store.removeValue(forKey: "k.int")
        #expect(!store.hasValue(forKey: "k.int"))
        #expect(store.value("k.int", default: 5) == 5)
    }
}

struct PreferenceGroupTests {
    @Test
    func exposesDeclaredDefaultsBeforeAnythingIsWritten() {
        let (store, _) = makeStore()
        let behaviour = BehaviourSettings(store: store)

        #expect(behaviour.expandOnHover == true)
        #expect(behaviour.hoverDuration == BehaviourSettings.Defaults.hoverDuration)
        #expect(behaviour.autoCollapseOnLeave == true)
        #expect(behaviour.idleSessionCleanup == .twoHours)
        #expect(behaviour.reminderDelay == .off)
        #expect(behaviour.quietFocusModes.isEmpty)
    }

    @Test
    func writesSurviveANewInstanceOnTheSameSuite() {
        let (store, _) = makeStore()
        let behaviour = BehaviourSettings(store: store)

        behaviour.expandOnHover = false
        behaviour.hoverDuration = 0.4
        behaviour.idleSessionCleanup = .never

        let reloaded = BehaviourSettings(store: store)
        #expect(reloaded.expandOnHover == false)
        #expect(reloaded.hoverDuration == 0.4)
        #expect(reloaded.idleSessionCleanup == .never)
    }

    /// The whole point of hand-writing the computed properties: SwiftUI has to be
    /// told the value changed.
    @Test
    func mutatingAPropertyNotifiesObservers() {
        let (store, _) = makeStore()
        let behaviour = BehaviourSettings(store: store)
        let counter = ChangeCounter()

        withObservationTracking {
            _ = behaviour.expandOnHover
        } onChange: {
            counter.increment()
        }

        behaviour.expandOnHover = false
        #expect(counter.count == 1)
    }

    @Test
    func observationIsScopedToTheMutatedProperty() {
        let (store, _) = makeStore()
        let behaviour = BehaviourSettings(store: store)
        let counter = ChangeCounter()

        withObservationTracking {
            _ = behaviour.expandOnHover
        } onChange: {
            counter.increment()
        }

        behaviour.hideInFullscreen = true
        #expect(counter.count == 0)
    }

    @Test
    func resetDropsTheStoredValue() {
        let (store, _) = makeStore()
        let display = DisplaySettings(store: store)

        display.contentFontSize = 15
        #expect(display.isCustomised(DisplaySettings.Keys.contentFontSize))

        display.reset(\.contentFontSize, DisplaySettings.Keys.contentFontSize)
        #expect(!display.isCustomised(DisplaySettings.Keys.contentFontSize))
        #expect(display.contentFontSize == DisplaySettings.Defaults.contentFontSize)
    }

    @Test
    func quietFocusModeTogglingKeepsDeclarationOrder() {
        let (store, _) = makeStore()
        let behaviour = BehaviourSettings(store: store)

        behaviour.setQuiet(true, during: .sleep)
        behaviour.setQuiet(true, during: .doNotDisturb)
        behaviour.setQuiet(true, during: .work)

        #expect(behaviour.quietFocusModes == ["doNotDisturb", "work", "sleep"])
        #expect(behaviour.isQuiet(during: .work))

        behaviour.setQuiet(false, during: .work)
        #expect(behaviour.quietFocusModes == ["doNotDisturb", "sleep"])
        #expect(!behaviour.isQuiet(during: .work))
    }

    /// Two groups sharing a suite must not collide on key names.
    @Test
    func groupKeysAreUnique() {
        let behaviourKeys = [
            BehaviourSettings.Keys.expandOnHover,
            BehaviourSettings.Keys.hoverDuration,
            BehaviourSettings.Keys.autoExpandOnAgentTeamComplete,
            BehaviourSettings.Keys.hideInFullscreen,
            BehaviourSettings.Keys.smartSuppression,
            BehaviourSettings.Keys.autoHideWhenIdle,
            BehaviourSettings.Keys.autoCollapseOnLeave,
            BehaviourSettings.Keys.autoRevealDwell,
            BehaviourSettings.Keys.dismissOnOutsideClick,
            BehaviourSettings.Keys.disableClickToJump,
            BehaviourSettings.Keys.expandOnCompletion,
            BehaviourSettings.Keys.childAgentNotificationTiming,
            BehaviourSettings.Keys.reminderDelay,
            BehaviourSettings.Keys.remindNeedsResponse,
            BehaviourSettings.Keys.remindCompletedWork,
            BehaviourSettings.Keys.quietFocusModes,
            BehaviourSettings.Keys.quietWhenScreenObscured,
            BehaviourSettings.Keys.quietWhenScreenCaptured,
            BehaviourSettings.Keys.idleSessionCleanup,
        ]
        let displayKeys = [
            DisplaySettings.Keys.contentFontSize,
            DisplaySettings.Keys.maxPanelHeight,
            DisplaySettings.Keys.maxPanelWidth,
            DisplaySettings.Keys.completionCardHeight,
            DisplaySettings.Keys.notchHeightOverride,
            DisplaySettings.Keys.notchWidthOverride,
            DisplaySettings.Keys.showTasks,
            DisplaySettings.Keys.showSubagents,
            DisplaySettings.Keys.showAgentActivity,
            DisplaySettings.Keys.showModel,
            DisplaySettings.Keys.showReasoningEffort,
            DisplaySettings.Keys.showWorktree,
            DisplaySettings.Keys.showProjectName,
        ]

        let all = behaviourKeys + displayKeys
        #expect(Set(all).count == all.count)
    }

    /// These groups must not reach into keys `AppModel` already owns.
    @Test
    func groupKeysDoNotCollideWithExistingAppModelKeys() {
        let appModelOwned: Set<String> = [
            "overlay.sound.muted",
            "app.showDockIcon",
            "app.hapticFeedbackEnabled",
            "app.showCodexUsage",
            "app.suppressFrontmostNotifications",
            "feature.completionReply.enabled",
            "launchAtLogin.autoRegistered",
            "watch.notification.enabled",
        ]

        let ours: Set<String> = [
            BehaviourSettings.Keys.expandOnHover,
            BehaviourSettings.Keys.autoCollapseOnLeave,
            DisplaySettings.Keys.contentFontSize,
            DisplaySettings.Keys.showTasks,
        ]

        #expect(ours.isDisjoint(with: appModelOwned))
    }
}

struct FeatureAvailabilityTests {
    /// Nothing may be marked implemented before its behaviour actually ships.
    /// When a capability lands, add it to the ledger and update this expectation
    /// in the same commit.
    @Test
    func nothingIsMarkedImplementedYet() {
        #expect(PendingCapability.implemented.isEmpty)
    }

    @Test
    func unimplementedCapabilitiesReportAsPending() {
        for capability in PendingCapability.allCases where !capability.isImplemented {
            let availability = FeatureAvailability(capability)
            #expect(!availability.isReady)
            #expect(availability.pendingCapability == capability)
        }
    }

    @Test
    func everyCapabilityHasADistinctExplanationKey() {
        let keys = PendingCapability.allCases.map(\.explanationKey)
        #expect(Set(keys).count == keys.count)
        #expect(keys.allSatisfy { $0.hasPrefix("settings.pending.") })
    }
}
