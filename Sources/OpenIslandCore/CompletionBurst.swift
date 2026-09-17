import Foundation

/// One shard of light thrown out of the notch when a session finishes, in
/// units of the burst's own reach so the same frame fits any screen.
public struct CompletionBurstShard: Equatable, Sendable {
    /// Offset from the burst origin: x to the right, y downward, each as a
    /// fraction of the burst's reach.
    public let x: Double
    public let y: Double
    /// Edge length in points.
    public let size: Double
    public let rotationDegrees: Double
    public let opacity: Double
    /// Whether this shard takes the accent colour rather than white.
    public let isAccent: Bool
}

/// The "clear" burst that plays out of the notch as a session completes:
/// a flare along the notch's lower edge, two wide shockwave rings, and shards
/// of light thrown down and outward.
///
/// A pure function of elapsed time, like `LinkstartSequence`: a dropped frame
/// changes one picture, never where the burst is.
public enum CompletionBurst: Sendable {
    public static let duration: TimeInterval = 1.1
    public static let shardCount = 28

    /// The flare: 0…1 of its full width, and how bright it is.
    public static func flare(at elapsed: TimeInterval) -> (width: Double, opacity: Double) {
        guard elapsed >= 0, elapsed < duration else { return (0, 0) }
        let width = easeOut(elapsed / 0.25)
        let opacity = elapsed < 0.08 ? elapsed / 0.08 : 1 - easeOut((elapsed - 0.08) / 0.5)
        return (width, max(0, opacity))
    }

    /// The shockwave rings: radius as a fraction of reach, and opacity. The
    /// second ring trails the first by 0.12s.
    public static func rings(at elapsed: TimeInterval) -> [(radius: Double, opacity: Double)] {
        [0.0, 0.12].compactMap { delay in
            let t = (elapsed - delay) / 0.7
            guard t > 0, t < 1 else { return nil }
            return (radius: easeOut(t), opacity: 0.8 * (1 - t))
        }
    }

    /// Every shard at this moment. Empty before the burst and after it ends.
    public static func shards(at elapsed: TimeInterval) -> [CompletionBurstShard] {
        guard elapsed > 0, elapsed < duration else { return [] }
        let t = elapsed / duration
        let travel = easeOut(t)
        let fadeIn = min(elapsed / 0.06, 1)
        let fadeOut = 1 - t * t

        return (0..<shardCount).map { index in
            // Thrown into the lower half-plane: 10°…170°, where 90° is straight down.
            let angle = (10 + 160 * unitHash(index, salt: 1)) * .pi / 180
            let reach = 0.35 + 0.65 * unitHash(index, salt: 2)
            let spin = (unitHash(index, salt: 3) - 0.5) * 540
            return CompletionBurstShard(
                x: cos(angle) * reach * travel,
                // A little gravity, so they arc rather than fly in straight lines.
                y: sin(angle) * reach * travel + 0.18 * t * t,
                size: 3 + 5 * unitHash(index, salt: 4),
                rotationDegrees: 45 + spin * t,
                opacity: fadeIn * fadeOut,
                isAccent: unitHash(index, salt: 5) < 0.6
            )
        }
    }

    private static func easeOut(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return 1 - pow(1 - x, 3)
    }

    /// SplitMix64 — a stable 0..<1 per shard, so every burst is the same shape.
    private static func unitHash(_ index: Int, salt: UInt64) -> Double {
        var z = UInt64(truncatingIfNeeded: index) &* 0x9E37_79B9_7F4A_7C15 &+ salt &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
