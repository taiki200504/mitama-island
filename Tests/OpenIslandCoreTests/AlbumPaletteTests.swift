import Testing
@testable import OpenIslandCore

@Suite("Album artwork palette quantization")
struct AlbumPaletteTests {
    /// Builds `width * height` opaque RGBA pixels, all the given colour.
    private func solidPixels(_ r: UInt8, _ g: UInt8, _ b: UInt8, count: Int) -> [UInt8] {
        var samples: [UInt8] = []
        samples.reserveCapacity(count * 4)
        for _ in 0..<count {
            samples.append(contentsOf: [r, g, b, 255])
        }
        return samples
    }

    @Test("A single-colour image reports the same dominant and secondary colour")
    func singleColour() {
        let samples = solidPixels(200, 40, 40, count: 16)
        let (dominant, secondary) = AlbumPalette.quantize(rgbaSamples: samples, width: 4, height: 4)
        #expect(dominant == secondary)
        #expect(dominant.red > 150)
        #expect(dominant.green < 100)
    }

    @Test("Two colours are returned in order of how much of the image they cover")
    func twoColours() {
        // 12 red pixels, 4 blue — red must win as dominant.
        var samples = solidPixels(220, 20, 20, count: 12)
        samples.append(contentsOf: solidPixels(20, 20, 220, count: 4))
        let (dominant, secondary) = AlbumPalette.quantize(rgbaSamples: samples, width: 4, height: 4)

        #expect(dominant.red > dominant.blue)
        #expect(secondary.blue > secondary.red)
        #expect(dominant != secondary)
    }

    @Test("Fully transparent pixels are skipped")
    func transparentPixelsAreSkipped() {
        var samples: [UInt8] = []
        // 4 transparent pixels that would otherwise dominate...
        for _ in 0..<4 { samples.append(contentsOf: [0, 0, 0, 0]) }
        // ...and one opaque green pixel that should win instead.
        samples.append(contentsOf: [10, 200, 10, 255])
        let (dominant, _) = AlbumPalette.quantize(rgbaSamples: samples, width: 5, height: 1)
        #expect(dominant.green > 150)
    }

    @Test("No usable pixels at all falls back to a neutral grey")
    func emptyFallsBackToNeutral() {
        let (dominant, secondary) = AlbumPalette.quantize(rgbaSamples: [], width: 0, height: 0)
        #expect(dominant == secondary)
        #expect(dominant.red == dominant.green)
        #expect(dominant.green == dominant.blue)
    }
}
