import Testing
@testable import OpenIslandCore

@Suite("Island level")
struct IslandLevelTests {
    @Test("The curve: 0 → Lv1, 5 → Lv2, 15 → Lv3, 30 → Lv4")
    func curve() {
        #expect(IslandLevel.level(forCompletions: 0) == 1)
        #expect(IslandLevel.level(forCompletions: 4) == 1)
        #expect(IslandLevel.level(forCompletions: 5) == 2)
        #expect(IslandLevel.level(forCompletions: 14) == 2)
        #expect(IslandLevel.level(forCompletions: 15) == 3)
        #expect(IslandLevel.level(forCompletions: 30) == 4)
        #expect(IslandLevel.level(forCompletions: -3) == 1)
    }

    @Test("A level-up is reported exactly on the completion that crosses it")
    func levelReached() {
        #expect(IslandLevel.levelReached(from: 4, to: 5) == 2)
        #expect(IslandLevel.levelReached(from: 5, to: 6) == nil)
        #expect(IslandLevel.levelReached(from: 14, to: 15) == 3)
        #expect(IslandLevel.levelReached(from: 0, to: 0) == nil)
    }

    @Test("Progress runs 0 up to just under 1 within a level")
    func progress() {
        #expect(IslandLevel.progress(forCompletions: 5) == 0)
        #expect(IslandLevel.progress(forCompletions: 10) == 0.5)
        #expect(IslandLevel.progress(forCompletions: 14) < 1)
    }
}
