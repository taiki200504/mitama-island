import Testing
@testable import OpenIslandApp

@MainActor
struct IslandSoundProfileTests {
    @Test
    func everyEventHasADefaultSoundName() {
        for event in NotificationSoundEvent.allCases {
            #expect(!IslandSoundProfile.sao.soundName(for: event).isEmpty)
        }
    }

    /// Catches a default that points at a cue whose file never shipped: the
    /// resource would fall through to a mismatched (or missing) system sound
    /// with no warning at build time.
    @Test
    func everyBundledDefaultResolvesToAFile() {
        for event in NotificationSoundEvent.allCases {
            let name = IslandSoundProfile.sao.soundName(for: event)
            guard name.hasPrefix("ui-") else { continue }
            #expect(
                NotificationSoundService.bundledSoundURL(named: name) != nil,
                "\(name), the default for \(event), has no bundled file"
            )
        }
    }

    /// The gesture-driven open and the ordinary open are the same moment
    /// reached two different ways, so they share a default on purpose — see
    /// `IslandSoundProfile.soundName(for:)`. This only pins down that the
    /// sharing is deliberate and not, say, `islandClosed` leaking in too.
    @Test
    func gestureOpenSharesTheOrdinaryOpenDefault() {
        let gesture = IslandSoundProfile.sao.soundName(for: .islandOpenedByGesture)
        let opened = IslandSoundProfile.sao.soundName(for: .islandOpened)
        #expect(gesture == opened)
        #expect(gesture != IslandSoundProfile.sao.soundName(for: .islandClosed))
    }
}
