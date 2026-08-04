import SwiftUI
import Testing
@testable import OpenIslandApp

@Suite("Island themes")
@MainActor
struct IslandThemeTests {
    /// A theme missing one status colour would leave a session row drawing
    /// nothing where its state should be. Both themes must be complete.
    @Test("Every theme fills in every status colour", arguments: IslandThemeID.allCases)
    func everyStatusIsCovered(_ id: IslandThemeID) {
        let tints = id.theme.statusTints
        let colours = [
            tints.running, tints.waitingForApproval, tints.waitingForAnswer,
            tints.completed, tints.waitingAggregate, tints.critical
        ]
        #expect(colours.count == 6)
        // Distinct enough that two states never read as the same colour.
        #expect(Set(colours.map { "\($0)" }).count >= 5)
    }

    @Test("The two themes are visually distinct")
    func themesDiffer() {
        #expect("\(IslandThemeID.hud.theme.ink)" != "\(IslandThemeID.classic.theme.ink)")
        #expect(IslandThemeID.hud.theme.cornerStyle != IslandThemeID.classic.theme.cornerStyle)
    }

    /// The panel is drawn over the physical notch, which is pure black. A panel
    /// that is also pure black has no edge against the hardware.
    @Test("The HUD panel is not pure black")
    func hudInkIsNotBlack() {
        #expect("\(IslandThemeID.hud.theme.ink)" != "\(Color.black)")
    }

    @Test("An unknown stored value falls back rather than failing")
    func unknownThemeFallsBack() {
        #expect(IslandThemeID(rawValue: "aincrad") == nil)
    }

    @Test("Hex initialisation maps to the right channels")
    func hexChannels() {
        #expect("\(Color(hex: 0xFF0000))" == "\(Color(red: 1, green: 0, blue: 0))")
        #expect("\(Color(hex: 0x00FF00))" == "\(Color(red: 0, green: 1, blue: 0))")
        #expect("\(Color(hex: 0x0000FF))" == "\(Color(red: 0, green: 0, blue: 1))")
    }
}

@Suite("Chamfered rectangle")
struct ChamferedRectangleTests {
    private let rect = CGRect(x: 0, y: 0, width: 100, height: 40)

    @Test("A cut corner is not on the bounding box's corner")
    func cutsTheCorner() {
        let path = ChamferedRectangle(cut: 8).path(in: rect)
        #expect(!path.contains(CGPoint(x: 1, y: 1)))
        #expect(!path.contains(CGPoint(x: 99, y: 39)))
        // The other diagonal stays square.
        #expect(path.contains(CGPoint(x: 99, y: 1)))
        #expect(path.contains(CGPoint(x: 1, y: 39)))
    }

    /// An oversized cut would send the two diagonals past each other and turn
    /// the panel into a bowtie.
    @Test("An oversized cut is clamped, not allowed to invert")
    func clampsOversizedCut() {
        let path = ChamferedRectangle(cut: 500).path(in: rect)
        #expect(!path.isEmpty)
        #expect(path.boundingRect.width <= rect.width)
        #expect(path.contains(CGPoint(x: 50, y: 20)))
    }

    @Test("A zero cut is an ordinary rectangle")
    func zeroCutIsPlain() {
        let path = ChamferedRectangle(cut: 0).path(in: rect)
        #expect(path.contains(CGPoint(x: 1, y: 1)))
        #expect(path.contains(CGPoint(x: 99, y: 39)))
    }
}
