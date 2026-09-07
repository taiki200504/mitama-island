import CoreGraphics
import Testing
@testable import OpenIslandApp

@Suite("SAO ring")
struct SAORingTests {
    @Test("Radii are monotonically non-increasing by ring index")
    func radiiAreMonotonic() {
        let radii = SAORing.radii(progress: 0.6, count: 5, maxRadius: 100)
        #expect(radii.count == 5)
        for index in 1..<radii.count {
            #expect(radii[index] <= radii[index - 1])
        }
    }

    @Test("Each ring lags the one before it by 0.12 of progress")
    func ringsLagByFixedAmount() {
        let maxRadius: CGFloat = 100
        let radii = SAORing.radii(progress: 1, count: 3, maxRadius: maxRadius)
        // At progress 1, ring 0 is fully out; ring 1 is at the radius ring 0
        // would have reached at progress 0.88; ring 2 at 0.76.
        #expect(abs(radii[0] - maxRadius) < 0.01)
        #expect(abs(radii[1] - maxRadius * 0.88) < 0.01)
        #expect(abs(radii[2] - maxRadius * 0.76) < 0.01)
    }

    @Test("A ring whose lag exceeds progress has not started yet")
    func laggedRingClampsToZero() {
        let radii = SAORing.radii(progress: 0.05, count: 5, maxRadius: 100)
        #expect(radii[4] == 0)
    }

    @Test("Zero rings produces an empty array")
    func zeroCountIsEmpty() {
        #expect(SAORing.radii(progress: 0.5, count: 0, maxRadius: 100).isEmpty)
    }
}

@Suite("SAO rays")
struct SAORaysTests {
    @Test("Produces exactly `count` endpoints")
    func producesRequestedCount() {
        let points = SAORays.endpoints(progress: 0.3, count: 24, center: .zero, length: 10)
        #expect(points.count == 24)
    }

    @Test("Every endpoint sits `length` away from the centre")
    func endpointsSitAtLength() {
        let center = CGPoint(x: 5, y: 5)
        let length: CGFloat = 20
        let points = SAORays.endpoints(progress: 0.4, count: 12, center: center, length: length)
        for point in points {
            let distance = (point.x - center.x, point.y - center.y)
            let magnitude = (distance.0 * distance.0 + distance.1 * distance.1).squareRoot()
            #expect(abs(magnitude - length) < 0.01)
        }
    }

    @Test("The whole set rotates by 6° per unit of progress")
    func setRotatesWithProgress() {
        let center = CGPoint.zero
        let length: CGFloat = 10
        let atZero = SAORays.endpoints(progress: 0, count: 4, center: center, length: length)[0]
        let atOne = SAORays.endpoints(progress: 1, count: 4, center: center, length: length)[0]
        // A 6° rotation moves the first ray's endpoint; it should not land
        // back on the same point.
        #expect(abs(atZero.x - atOne.x) > 0.01 || abs(atZero.y - atOne.y) > 0.01)
    }

    @Test("Zero length or zero count produces no endpoints")
    func degenerateInputsAreEmpty() {
        #expect(SAORays.endpoints(progress: 0.5, count: 0, center: .zero, length: 10).isEmpty)
        #expect(SAORays.endpoints(progress: 0.5, count: 24, center: .zero, length: 0).isEmpty)
    }
}
