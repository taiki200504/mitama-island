import SwiftUI
import Testing
@testable import OpenIslandApp

@Suite("SAO gauge shape")
struct SAOGaugeShapeTests {
    private let rect = CGRect(x: 0, y: 0, width: 100, height: 20)

    @Test("An empty gauge draws nothing")
    func emptyFractionIsEmpty() {
        let path = SAOGaugeShape(fraction: 0).path(in: rect)
        #expect(path.isEmpty)
    }

    @Test("A half-full gauge is half as wide as the track")
    func halfFractionIsHalfWidth() {
        let path = SAOGaugeShape(fraction: 0.5).path(in: rect)
        #expect(abs(path.boundingRect.width - rect.width / 2) < 0.01)
    }

    @Test("A full gauge spans the whole track")
    func fullFractionSpansTrack() {
        let path = SAOGaugeShape(fraction: 1).path(in: rect)
        #expect(abs(path.boundingRect.width - rect.width) < 0.01)
    }

    @Test("isTrack ignores fraction and always spans the full width")
    func trackIgnoresFraction() {
        let path = SAOGaugeShape(fraction: 0.2, isTrack: true).path(in: rect)
        #expect(abs(path.boundingRect.width - rect.width) < 0.01)
    }

    @Test("The right edge is diagonal at the theme's slope")
    func rightEdgeFollowsSlope() {
        let path = SAOGaugeShape(fraction: 1, isTrack: true).path(in: rect)
        // The top-right vertex sits `height * slope` to the left of the
        // bottom-right vertex — the same cut angle every other shape in this
        // theme uses.
        let expectedDx = rect.height * SAOGrammar.Metric.slope
        #expect(path.contains(CGPoint(x: rect.maxX - expectedDx - 1, y: 1)))
        #expect(!path.contains(CGPoint(x: rect.maxX - expectedDx + 1, y: 1)))
    }

    @Test("Fraction is clamped to 0...1")
    func fractionIsClamped() {
        let over = SAOGaugeShape(fraction: 2).path(in: rect)
        let full = SAOGaugeShape(fraction: 1).path(in: rect)
        #expect(abs(over.boundingRect.width - full.boundingRect.width) < 0.01)

        let under = SAOGaugeShape(fraction: -1).path(in: rect)
        #expect(under.isEmpty)
    }
}
