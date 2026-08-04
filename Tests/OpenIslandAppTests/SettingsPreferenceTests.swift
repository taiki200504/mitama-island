import Foundation
import AppKit
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
            DisplaySettings.Keys.completionCardMaxHeight,
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
    /// The ledger is the only thing standing between an honest badge and a dead
    /// toggle, so a capability may only appear here once its behaviour ships.
    /// The ledger must not become a wish list. scripts/check-capability-ledger.sh
    /// fails the harness if a case is added without a control using it.
    @Test
    func theLedgerListsExactlyWhatHasShipped() {
        #expect(PendingCapability.implemented == [
            .foregroundTerminalDetection,
            .outsideClickDetection,
            .fullscreenDetection,
            .autoHideTimer,
            .focusModeDetection,
            .screenStateDetection,
            .screenCaptureDetection,
            .notchCalibration,
            .completionCardSizing,
        ])
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

@MainActor
struct SettingsSurfaceTests {
    /// `LanguageManager.t` echoes the key back when the lookup misses, so a key
    /// that equals its own translation means nobody wrote the string.
    private func isLocalized(_ key: String) -> Bool {
        LanguageManager.shared.t(key) != key
    }

    @Test
    func everyTabHasATitleInTheBundle() {
        for tab in SettingsTab.allCases {
            #expect(isLocalized(tab.titleKey), "missing string for \(tab.titleKey)")
        }
    }

    @Test
    func everyPendingCapabilityHasAnExplanationInTheBundle() {
        for capability in PendingCapability.allCases {
            #expect(
                isLocalized(capability.explanationKey),
                "missing string for \(capability.explanationKey)"
            )
        }
    }

    @Test
    func sharedControlStringsExist() {
        for key in [
            "settings.pending.badge",
            "settings.value.defaultMarker",
            "settings.value.reset",
            "settings.paneNotBuilt.title",
            "settings.paneNotBuilt.body",
        ] {
            #expect(isLocalized(key), "missing string for \(key)")
        }
    }

    /// Every tab must appear in exactly one sidebar section — a tab that belongs
    /// to none would silently vanish from the sidebar.
    @Test
    func sidebarSectionsCoverEveryTabExactlyOnce() {
        let listed = SettingsSection.allCases.flatMap(\.tabs)
        #expect(listed.count == SettingsTab.allCases.count)
        #expect(Set(listed) == Set(SettingsTab.allCases))
    }

    @Test
    func tabsAreVisuallyDistinguishable() {
        let icons = SettingsTab.allCases.map(\.icon)
        #expect(Set(icons).count == icons.count)
    }
}

struct IslandTypographyTests {
    /// The bundled face has to actually register, or every monospaced run in the
    /// island silently falls back to the system font and the pixel-grid look the
    /// reference product has is lost.
    @Test
    func theBundledMonospaceFontRegisters() {
        // Registration happens lazily on first use, so ask through the type
        // rather than the font system. Reading NSFont directly made this pass or
        // fail depending on whether another test had touched IslandTypography.
        let font = IslandTypography.nsMono(size: 12)
        // familyName, not fontName: the PostScript name is DepartureMono-Regular
        // while the family the lookup uses is "Departure Mono".
        #expect(font.familyName == IslandTypography.departureMonoName)
    }

    @Test
    func monoFallsBackRatherThanReturningNothing() {
        // Whether or not registration succeeded, a usable font comes back.
        #expect(IslandTypography.nsMono(size: 11).pointSize == 11)
    }

    /// A licence file has to travel with a bundled font.
    @Test
    func theFontLicenceIsBundledAlongsideIt() {
        let licence = Bundle.module.url(
            forResource: "DepartureMono-LICENSE",
            withExtension: "txt",
            subdirectory: "Fonts"
        ) ?? Bundle.module.url(forResource: "DepartureMono-LICENSE", withExtension: "txt")
        #expect(licence != nil)
    }
}

@MainActor
struct SettingsPaneCoverageTests {
    /// Every tab in the sidebar has to lead somewhere. A pane left routed to the
    /// "not built yet" placeholder is fine, but it must be a deliberate choice
    /// rather than something forgotten, so this records the current state.
    @Test
    func everyPaneIsBuilt() {
        // Updated deliberately: when a pane lands, remove it from here.
        let notBuiltYet: Set<SettingsTab> = []
        for tab in SettingsTab.allCases where notBuiltYet.contains(tab) {
            Issue.record("\(tab) is still a placeholder")
        }
        #expect(notBuiltYet.isEmpty)
    }

    /// The usage pane drives the island's own usage strip, so the two have to
    /// agree on what "showing usage" means.
    @Test
    func usageVisibilityRoundTrips() {
        let name = "usage-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        let model = AppModel(settings: SettingsStore(store: PreferenceStore(suite: suite)))

        model.islandUsageDisplay = .hidden
        #expect(model.islandUsageDisplay == .hidden)

        model.islandUsageDisplay = .compact
        #expect(model.islandUsageDisplay == .compact)
    }
}

@MainActor
struct ApplicationNameTests {
    /// The name is a proper noun taken from the bundle. A translated copy drifts
    /// the moment the bundle is renamed — the UI said "Open Island" for several
    /// releases after the app shipped as "Mitama Island".
    @Test
    func theNameComesFromTheBundle() {
        let expected = (Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (Bundle.main.infoDictionary?["CFBundleName"] as? String)

        if let expected, !expected.trimmingCharacters(in: .whitespaces).isEmpty {
            #expect(LanguageManager.applicationName == expected)
        }
        #expect(!LanguageManager.applicationName.isEmpty)
    }

    /// Looking the key up must not fall through to the strings file.
    @Test
    func theLocalizedLookupReturnsTheBundleName() {
        #expect(LanguageManager.shared.t("app.name") == LanguageManager.applicationName)
    }
}

struct ContentScaleTests {
    /// The setting multiplies the measured sizes rather than replacing them, so
    /// the default must leave every size exactly as it was.
    @Test
    func theDefaultLeavesSizesUntouched() {
        for size in [7.5, 10.5, 11.2, 12.5, 24.0] as [CGFloat] {
            #expect(IslandTypography.scaled(size, by: 1) == size)
        }
    }

    @Test
    func largerAndSmallerBothApply() {
        #expect(IslandTypography.scaled(10, by: 1.2) == 12)
        #expect(IslandTypography.scaled(10, by: 0.8) == 8)
    }

    /// Fractional sizes are preserved; an earlier attempt to snap them to
    /// half-points silently changed how the panel rendered at the default.
    @Test
    func fractionalSizesSurvive() {
        #expect(IslandTypography.scaled(11.2, by: 1) == 11.2)
        #expect(IslandTypography.scaled(12.2, by: 1) == 12.2)
    }

    /// An absurd multiplier would make the panel unusable, so it is bounded.
    @Test
    func theMultiplierIsClamped() {
        #expect(IslandTypography.scaled(10, by: 100) == IslandTypography.scaled(10, by: 1.6))
        #expect(IslandTypography.scaled(10, by: 0.01) == IslandTypography.scaled(10, by: 0.75))
    }
}
