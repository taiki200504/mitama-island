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

    /// Themes are allowed to add their own motion, but the two existing looks
    /// must preserve the panel timing and frame that people already know.
    @Test("HUD and Classic preserve the legacy motion and frame")
    func legacyThemesPreserveVisualProfile() {
        let expectedOpen = "\(Animation.spring(response: 0.3, dampingFraction: 0.9, blendDuration: 0))"
        let expectedClose = "\(Animation.smooth(duration: 0.15))"
        let expectedPop = "\(Animation.spring(response: 0.3, dampingFraction: 0.5))"

        for theme in [IslandThemeID.hud.theme, IslandThemeID.classic.theme] {
            #expect("\(theme.animationProfile.open)" == expectedOpen)
            #expect("\(theme.animationProfile.close)" == expectedClose)
            #expect("\(theme.animationProfile.pop)" == expectedPop)
            #expect(theme.borderStyle.width == 1)
            #expect(theme.borderStyle.opacity == 0.07)
            #expect(!theme.borderStyle.isDouble)
            #expect(theme.scanlineIntensity == 0)
        }
    }

    @Test("SAO is available and uses its themed scanlines")
    func saoThemeIsAvailable() {
        #expect(IslandThemeID.allCases.contains(.sao))
        #expect(IslandThemeID.sao.theme is SAOTheme)
        #expect(IslandThemeID.sao.theme.scanlineIntensity > 0)
        #expect(IslandThemeID.hud.theme.scanlineIntensity == 0)
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

@Suite("Island panel shape")
struct IslandPanelShapeTests {
    private let rect = CGRect(x: 0, y: 0, width: 100, height: 40)

    @Test("The corner style decides the shape")
    func styleDecidesTheShape() {
        let chamfered = IslandPanelShape(cornerRadius: 8, style: .chamfered).path(in: rect)
        let rounded = IslandPanelShape(cornerRadius: 8, style: .rounded).path(in: rect)
        // The chamfer cuts the top-left corner off the diagonal a rounded
        // corner would curve through.
        #expect(!chamfered.contains(CGPoint(x: 2, y: 2)))
        #expect(chamfered.boundingRect == rounded.boundingRect)
    }

    /// `strokeBorder` insets the shape before stroking. If insetting were
    /// ignored, every border would bleed half a line width outside its fill.
    @Test("Insetting shrinks the shape")
    func insettingShrinks() {
        let full = IslandPanelShape(cornerRadius: 8, style: .chamfered).path(in: rect)
        let inset = IslandPanelShape(cornerRadius: 8, style: .chamfered).inset(by: 4).path(in: rect)
        #expect(inset.boundingRect.width < full.boundingRect.width)
        #expect(inset.boundingRect.height < full.boundingRect.height)
    }

    /// Insetting past the corner size must not produce a negative radius.
    @Test("A deep inset stays a valid shape")
    func deepInsetIsValid() {
        let path = IslandPanelShape(cornerRadius: 4, style: .chamfered).inset(by: 10).path(in: rect)
        #expect(!path.isEmpty)
        #expect(path.boundingRect.width > 0)
    }
}
