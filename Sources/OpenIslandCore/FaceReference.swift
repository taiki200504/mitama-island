import Foundation

/// A privacy-preserving collection of face feature vectors; it never contains face imagery.
public struct FaceReference: Equatable, Codable, Sendable {
    public var samples: [[Float]]

    public init(samples: [[Float]]) {
        self.samples = samples
    }

    /// A mean vector makes registration less sensitive to one poorly lit enrollment frame.
    public var representativeVector: [Float]? {
        guard let first = samples.first, !first.isEmpty,
              samples.allSatisfy({ $0.count == first.count })
        else { return nil }

        return (0..<first.count).map { index in
            samples.map { $0[index] }.reduce(0, +) / Float(samples.count)
        }
    }

    public static func euclideanDistance(_ lhs: [Float], _ rhs: [Float]) -> Float? {
        guard lhs.count == rhs.count else { return nil }
        return sqrt(zip(lhs, rhs).reduce(Float.zero) { partial, pair in
            let delta = pair.0 - pair.1
            return partial + delta * delta
        })
    }

    public func isLikelyMatch(_ candidate: [Float], threshold: Float) -> Bool {
        guard let representativeVector,
              let distance = Self.euclideanDistance(representativeVector, candidate)
        else { return false }
        return distance <= threshold
    }

    public func encodedJSON() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public init(jsonData: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: jsonData)
    }
}
