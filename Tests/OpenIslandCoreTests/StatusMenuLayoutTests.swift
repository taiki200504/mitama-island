import Testing
@testable import OpenIslandCore

@Suite("Status item menu layout")
struct StatusMenuLayoutTests {
    private func inputs(
        isMuted: Bool = false,
        cameraIsWatching: Bool = false,
        cameraStaysOpen: Bool = false,
        shelfItemNames: [String] = [],
        waitingCount: Int = 0
    ) -> StatusMenuInputs {
        StatusMenuInputs(
            isMuted: isMuted,
            cameraIsWatching: cameraIsWatching,
            cameraStaysOpen: cameraStaysOpen,
            shelfItemNames: shelfItemNames,
            waitingCount: waitingCount
        )
    }

    @Test("Base order with nothing on the shelf")
    func baseOrderWithEmptyShelf() {
        let entries = StatusMenuLayout.entries(for: inputs())
        #expect(entries == [
            .openIsland(waitingCount: 0),
            .toggleMute(isMuted: false),
            .toggleCamera(isWatching: false),
            .separator,
            .settings,
            .quit,
        ])
    }

    @Test("Mute label follows the muted state")
    func muteLabelFollowsState() {
        let mutedEntries = StatusMenuLayout.entries(for: inputs(isMuted: true))
        #expect(mutedEntries.contains(.toggleMute(isMuted: true)))

        let unmutedEntries = StatusMenuLayout.entries(for: inputs(isMuted: false))
        #expect(unmutedEntries.contains(.toggleMute(isMuted: false)))
    }

    @Test("Camera label follows whether it is watching")
    func cameraLabelFollowsState() {
        let watching = StatusMenuLayout.entries(for: inputs(cameraIsWatching: true))
        #expect(watching.contains(.toggleCamera(isWatching: true)))

        let idle = StatusMenuLayout.entries(for: inputs(cameraIsWatching: false))
        #expect(idle.contains(.toggleCamera(isWatching: false)))
    }

    @Test("An empty shelf shows no shelf section at all")
    func emptyShelfHasNoSection() {
        let entries = StatusMenuLayout.entries(for: inputs(shelfItemNames: []))
        for entry in entries {
            if case .shelfHeader = entry { Issue.record("Did not expect a shelf header") }
            if case .shelfItem = entry { Issue.record("Did not expect a shelf item") }
            if case .clearShelf = entry { Issue.record("Did not expect a clear-shelf row") }
        }
    }

    @Test("A non-empty shelf adds a separator, header, rows and a clear action")
    func nonEmptyShelfAddsItsSection() {
        let entries = StatusMenuLayout.entries(for: inputs(shelfItemNames: ["a.txt", "b.png"]))
        #expect(entries == [
            .openIsland(waitingCount: 0),
            .toggleMute(isMuted: false),
            .toggleCamera(isWatching: false),
            .separator,
            .shelfHeader(count: 2),
            .shelfItem(name: "a.txt"),
            .shelfItem(name: "b.png"),
            .clearShelf,
            .separator,
            .settings,
            .quit,
        ])
    }

    @Test("At most 5 shelf rows show, even with more on the shelf")
    func shelfRowsCapAtFive() {
        let names = (1...7).map { "file\($0).txt" }
        let entries = StatusMenuLayout.entries(for: inputs(shelfItemNames: names))

        let shelfItemEntries = entries.filter {
            if case .shelfItem = $0 { return true }
            return false
        }
        #expect(shelfItemEntries.count == 5)
        // The header still names the true total, not the truncated count.
        #expect(entries.contains(.shelfHeader(count: 7)))
        #expect(entries.contains(.clearShelf))
    }

    @Test("The waiting count rides along on the open-island entry")
    func waitingCountIsCarriedByOpenIslandEntry() {
        let entries = StatusMenuLayout.entries(for: inputs(waitingCount: 3))
        #expect(entries.first == .openIsland(waitingCount: 3))
    }

    @Test("Row order never changes shape regardless of inputs")
    func orderIsStable() {
        let entries = StatusMenuLayout.entries(for: inputs(
            isMuted: true,
            cameraIsWatching: true,
            cameraStaysOpen: true,
            shelfItemNames: ["only.txt"],
            waitingCount: 1
        ))

        #expect(entries == [
            .openIsland(waitingCount: 1),
            .toggleMute(isMuted: true),
            .toggleCamera(isWatching: true),
            .separator,
            .shelfHeader(count: 1),
            .shelfItem(name: "only.txt"),
            .clearShelf,
            .separator,
            .settings,
            .quit,
        ])
    }
}
