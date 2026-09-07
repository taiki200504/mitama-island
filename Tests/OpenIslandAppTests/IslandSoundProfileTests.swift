import Testing
@testable import OpenIslandApp

/// Gesture feedback is distinct, so the physical pull-down action remains
/// recognizable even when other notifications arrive nearby.
struct IslandSoundProfileTests {
    @Test
    func everyEventHasADefaultSoundName() {
        for event in NotificationSoundEvent.allCases {
            #expect(!IslandSoundProfile.sao.soundName(for: event).isEmpty)
        }
    }

    @Test
    func gestureSoundIsUniqueAmongEvents() {
        let gesture = IslandSoundProfile.sao.soundName(for: .islandOpenedByGesture)
        #expect(gesture == "Submarine")
        #expect(
            NotificationSoundEvent.allCases
                .filter { $0 != .islandOpenedByGesture }
                .allSatisfy { IslandSoundProfile.sao.soundName(for: $0) != gesture }
        )
    }
}
