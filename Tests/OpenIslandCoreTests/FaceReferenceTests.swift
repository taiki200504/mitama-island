import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Face references")
struct FaceReferenceTests {
    @Test("Vectors with different dimensions have no distance")
    func rejectsDifferentDimensions() {
        #expect(FaceReference.euclideanDistance([0, 1], [0, 1, 2]) == nil)
    }

    @Test("Enrollment samples are averaged and survive JSON storage")
    func averagesAndRoundTripsJSON() throws {
        let reference = FaceReference(samples: [[0, 0], [2, 2]])
        #expect(reference.representativeVector == [1, 1])
        #expect(reference.isLikelyMatch([1.1, 0.9], threshold: 0.2))
        #expect(!reference.isLikelyMatch([2, 2], threshold: 0.2))
        #expect(try FaceReference(jsonData: reference.encodedJSON()) == reference)
    }
}
