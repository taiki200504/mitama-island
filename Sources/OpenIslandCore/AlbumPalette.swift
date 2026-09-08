import Foundation

/// A colour with no dependency on AppKit or CoreImage, so `AlbumPalette`
/// stays testable with plain byte arrays.
public struct RGB: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// Picks two representative colours out of an image's raw pixels for the
/// Now Playing surface's tint — a coarse bucketed histogram rather than
/// k-means or CoreImage's area-average filter. Album art only needs "roughly
/// this colour" for a glow, not a precise palette extraction.
public enum AlbumPalette {
    /// Buckets per channel. 4 (64 buckets total across R/G/B) is coarse
    /// enough that near-identical pixels always collapse into one bucket,
    /// but fine enough to tell orange from red.
    private static let bucketsPerChannel = 4
    private static let bucketSize = 256 / bucketsPerChannel

    /// `rgbaSamples` is 4 bytes per pixel (R, G, B, A) in row-major order,
    /// `width * height` pixels long. A pixel with alpha below 128 is
    /// skipped — mostly-transparent padding around non-square artwork
    /// carries no colour worth counting.
    ///
    /// Returns the two most common bucket colours, both equal to the same
    /// dominant colour when the image is effectively one colour (or empty,
    /// in which case both are a neutral grey).
    public static func quantize(rgbaSamples: [UInt8], width: Int, height: Int) -> (dominant: RGB, secondary: RGB) {
        var buckets: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]

        let pixelCount = width * height
        for pixel in 0..<pixelCount {
            let offset = pixel * 4
            guard offset + 3 < rgbaSamples.count else { break }
            guard rgbaSamples[offset + 3] >= 128 else { continue }

            let r = Int(rgbaSamples[offset])
            let g = Int(rgbaSamples[offset + 1])
            let b = Int(rgbaSamples[offset + 2])
            let key = (bucket(r) << 8) | (bucket(g) << 4) | bucket(b)

            var entry = buckets[key] ?? (0, 0, 0, 0)
            entry.count += 1
            entry.r += r
            entry.g += g
            entry.b += b
            buckets[key] = entry
        }

        guard !buckets.isEmpty else {
            let neutral = RGB(red: 128, green: 128, blue: 128)
            return (neutral, neutral)
        }

        let ranked = buckets.values.sorted { $0.count > $1.count }
        let dominant = average(ranked[0])
        let secondary = ranked.count > 1 ? average(ranked[1]) : dominant
        return (dominant, secondary)
    }

    private static func bucket(_ channel: Int) -> Int {
        min(bucketsPerChannel - 1, channel / bucketSize)
    }

    private static func average(_ entry: (count: Int, r: Int, g: Int, b: Int)) -> RGB {
        RGB(
            red: UInt8(clamping: entry.r / entry.count),
            green: UInt8(clamping: entry.g / entry.count),
            blue: UInt8(clamping: entry.b / entry.count)
        )
    }
}
