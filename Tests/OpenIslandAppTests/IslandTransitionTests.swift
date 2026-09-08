import SwiftUI
import Testing
@testable import OpenIslandApp

@Suite("Island transition modifiers")
@MainActor
struct IslandTransitionTests {
    @Test("WidthWipe's animatable data round-trips both properties")
    func widthWipeRoundTrips() {
        var modifier = WidthWipe(progress: 0, yOffset: -12)
        #expect(modifier.animatableData.first == 0)
        #expect(modifier.animatableData.second == -12)

        modifier.animatableData = AnimatablePair(1, 0)
        #expect(modifier.progress == 1)
        #expect(modifier.yOffset == 0)
    }

    /// `VectorArithmetic` interpolation is what actually drives the
    /// animation frame by frame — a modifier whose pair does not average
    /// correctly would jump instead of wipe.
    @Test("WidthWipe interpolates linearly between its two states")
    func widthWipeInterpolatesLinearly() {
        let start = WidthWipe(progress: 0, yOffset: -12).animatableData
        let end = WidthWipe(progress: 1, yOffset: 0).animatableData
        let midpoint = start.interpolated(towards: end, amount: 0.5)
        #expect(midpoint.first == 0.5)
        #expect(midpoint.second == -6)
    }

    @Test("AxisScale's animatable data round-trips")
    func axisScaleRoundTrips() {
        var modifier = AxisScale(scale: 0.02, axis: .vertical)
        #expect(modifier.animatableData == 0.02)

        modifier.animatableData = 1
        #expect(modifier.scale == 1)
    }
}
