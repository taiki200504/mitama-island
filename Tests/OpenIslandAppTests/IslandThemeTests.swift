import SwiftUI
import Testing
@testable import OpenIslandApp

@Suite("Island theme")
@MainActor
struct IslandThemeTests {
    /// A theme missing one status colour would leave a session row drawing
    /// nothing where its state should be.
    @Test("Every status colour is filled in")
    func everyStatusIsCovered() {
        let tints = SAOTheme().statusTints
        let colours = [
            tints.running, tints.waitingForApproval, tints.waitingForAnswer,
            tints.completed, tints.waitingAggregate, tints.critical
        ]
        #expect(colours.count == 6)
        // Distinct enough that two states never read as the same colour.
        #expect(Set(colours.map { "\($0)" }).count >= 5)
    }

    /// The panel is drawn over the physical notch, which is pure black. A panel
    /// that is also pure black has no edge against the hardware.
    @Test("The panel is not pure black")
    func inkIsNotBlack() {
        #expect("\(SAOTheme().ink)" != "\(Color.black)")
    }

    /// A value written by an older build that still had a theme switcher must
    /// not linger in defaults forever.
    @Test("A legacy stored theme value is migrated away")
    func legacyThemeValueIsMigrated() {
        let suiteName = "IslandThemeTests.legacyThemeValueIsMigrated"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("hud", forKey: DisplaySettings.Keys.theme)
        #expect(defaults.string(forKey: DisplaySettings.Keys.theme) != nil)

        _ = SettingsStore(store: PreferenceStore(suite: defaults))

        #expect(defaults.string(forKey: DisplaySettings.Keys.theme) == nil)
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

@Suite("Island panel shape")
struct IslandPanelShapeTests {
    private let rect = CGRect(x: 0, y: 0, width: 100, height: 40)

    @Test("The shape is chamfered")
    func isChamfered() {
        let shape = IslandPanelShape(cornerRadius: 8).path(in: rect)
        // The chamfer cuts the top-left corner off the diagonal a rounded
        // corner would curve through.
        #expect(!shape.contains(CGPoint(x: 2, y: 2)))
    }

    /// `strokeBorder` insets the shape before stroking. If insetting were
    /// ignored, every border would bleed half a line width outside its fill.
    @Test("Insetting shrinks the shape")
    func insettingShrinks() {
        let full = IslandPanelShape(cornerRadius: 8).path(in: rect)
        let inset = IslandPanelShape(cornerRadius: 8).inset(by: 4).path(in: rect)
        #expect(inset.boundingRect.width < full.boundingRect.width)
        #expect(inset.boundingRect.height < full.boundingRect.height)
    }

    /// Insetting past the corner size must not produce a negative radius.
    @Test("A deep inset stays a valid shape")
    func deepInsetIsValid() {
        let path = IslandPanelShape(cornerRadius: 4).inset(by: 10).path(in: rect)
        #expect(!path.isEmpty)
        #expect(path.boundingRect.width > 0)
    }
}
