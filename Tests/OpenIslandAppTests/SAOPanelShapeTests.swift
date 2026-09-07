import SwiftUI
import Testing
@testable import OpenIslandApp

@Suite("SAO panel shape")
struct SAOPanelShapeTests {
    private let rect = CGRect(x: 0, y: 0, width: 100, height: 40)

    @Test("A cut corner's two vertices follow the theme's slope")
    func cutFollowsSlope() {
        let depth: CGFloat = 10
        let points = SAOPanelShape.vertices(in: rect, cuts: [.topLeading], depth: depth)
        #expect(points.count == 2)

        let horizontal = points[0]
        let vertical = points[1]
        // Both tangent points share the rect's own corner as their origin —
        // the horizontal one offset in x, the vertical one offset in y.
        let dx = horizontal.x - rect.minX
        let dy = vertical.y - rect.minY
        #expect(abs(dy - depth) < 0.01)
        #expect(abs(dx - depth * SAOGrammar.Metric.slope) < 0.01)
    }

    @Test("Every requested corner contributes exactly two vertices")
    func multipleCutsEachContributeTwoVertices() {
        let points = SAOPanelShape.vertices(
            in: rect,
            cuts: [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing],
            depth: 8
        )
        #expect(points.count == 8)
    }

    @Test("A cut corner is excluded from the path")
    func cutCornerIsExcludedFromPath() {
        let shape = SAOPanelShape(cornerRadius: 6, cuts: [.topLeading, .bottomTrailing], cutDepth: 10)
        let path = shape.path(in: rect)
        #expect(!path.contains(CGPoint(x: 1, y: 1)))
        #expect(!path.contains(CGPoint(x: 99, y: 39)))
        // The other diagonal is rounded, not cut, so a point well inside its
        // (smaller-radius) arc still counts as filled.
        #expect(path.contains(CGPoint(x: 96, y: 2)))
        #expect(path.contains(CGPoint(x: 4, y: 38)))
    }

    @Test("An uncut corner rounds instead of cutting")
    func uncutCornerRounds() {
        let shape = SAOPanelShape(cornerRadius: 6, cuts: [], cutDepth: 10)
        let path = shape.path(in: rect)
        // No corner is cut, so every corner is filled almost to the edge —
        // only a rounding this shallow could still contain a point this
        // close to the corner.
        #expect(path.contains(CGPoint(x: 1, y: 4)))
        #expect(path.contains(CGPoint(x: 4, y: 1)))
    }

    @Test("An oversized cut depth is clamped, not allowed to invert")
    func clampsOversizedDepth() {
        let shape = SAOPanelShape(cornerRadius: 6, cuts: [.topLeading, .bottomTrailing], cutDepth: 500)
        let path = shape.path(in: rect)
        #expect(!path.isEmpty)
        #expect(path.boundingRect.width <= rect.width)
        #expect(path.contains(CGPoint(x: 50, y: 20)))
    }

    @Test("Insetting shrinks the shape")
    func insettingShrinks() {
        let full = SAOPanelShape(cornerRadius: 6, cutDepth: 8).path(in: rect)
        let inset = SAOPanelShape(cornerRadius: 6, cutDepth: 8).inset(by: 4).path(in: rect)
        #expect(inset.boundingRect.width < full.boundingRect.width)
        #expect(inset.boundingRect.height < full.boundingRect.height)
    }

    @Test("A degenerate rect produces an empty path, not a crash")
    func degenerateRectIsEmpty() {
        let shape = SAOPanelShape(cornerRadius: 6, cutDepth: 8)
        #expect(shape.path(in: .zero).isEmpty)
    }
}
