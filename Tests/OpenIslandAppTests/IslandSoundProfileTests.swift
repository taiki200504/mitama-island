import Testing
@testable import OpenIslandApp

/// Gesture feedback is distinct in the SAO theme, so the physical pull-down
/// action remains recognizable even when other notifications arrive nearby.
struct IslandSoundProfileTests {
    @Test
    func gestureSoundIsThemeSpecificAndUniqueInSAO() {
        let standard = IslandSoundProfile.standard.soundName(for: .islandOpenedByGesture)
        let sao = IslandSoundProfile.sao.soundName(for: .islandOpenedByGesture)

        #expect(standard == "Bottle")
        #expect(sao == "Submarine")
        #expect(standard != sao)
        #expect(
            NotificationSoundEvent.allCases
                .filter { $0 != .islandOpenedByGesture }
                .allSatisfy { IslandSoundProfile.sao.soundName(for: $0) != sao }
        )
    }
}
