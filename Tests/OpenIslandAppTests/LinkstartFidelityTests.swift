import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Holds the sequence to the shape of the recording it was built from.
///
/// The picture was tuned against a reference by measuring both, because
/// nobody here can watch nineteen seconds of animation and say whether beat
/// eleven drifted. Two numbers per beat — how bright the frame is and how much
/// colour it carries — are enough to catch the drifts that matter: a screen
/// that goes blank, a panel that stops filling the frame, a wash that turns
/// the end dark instead of white.
///
/// The numbers are measurements, not the reference's pixels: nothing from the
/// recording is stored here or anywhere in the repository.
@MainActor
struct LinkstartFidelityTests {
    private struct Beat {
        let at: TimeInterval
        let brightness: Double
        let saturation: Double

        init(_ at: TimeInterval, brightness: Double, saturation: Double) {
            self.at = at
            self.brightness = brightness
            self.saturation = saturation
        }
    }

    /// Measured from the reference at 0.6s intervals.
    private static let beats: [Beat] = [
        Beat(0.2, brightness: 0.13, saturation: 0.00),
        Beat(0.8, brightness: 0.13, saturation: 0.00),
        Beat(2.0, brightness: 0.92, saturation: 0.00),
        Beat(3.2, brightness: 0.91, saturation: 0.00),
        Beat(3.8, brightness: 0.65, saturation: 0.20),
        Beat(4.4, brightness: 0.55, saturation: 0.37),
        Beat(5.0, brightness: 0.92, saturation: 0.00),
        Beat(6.2, brightness: 0.68, saturation: 0.48),
        Beat(7.4, brightness: 0.71, saturation: 0.37),
        Beat(8.6, brightness: 0.88, saturation: 0.07),
        Beat(9.2, brightness: 0.91, saturation: 0.03),
        Beat(10.4, brightness: 0.87, saturation: 0.06),
        Beat(11.6, brightness: 0.85, saturation: 0.09),
        Beat(12.8, brightness: 0.74, saturation: 0.24),
        Beat(14.6, brightness: 0.48, saturation: 0.00),
        Beat(15.8, brightness: 0.48, saturation: 0.00),
        Beat(17.0, brightness: 0.63, saturation: 0.60),
        Beat(18.2, brightness: 0.83, saturation: 0.31),
        Beat(18.8, brightness: 0.99, saturation: 0.02),
    ]

    /// Wide enough that a deliberate change of shade passes, tight enough that
    /// a beat going blank, dark or grey fails.
    private static let brightnessTolerance = 0.28
    private static let saturationTolerance = 0.32

    @Test
    func everyBeatKeepsTheShapeOfTheReference() throws {
        for beat in Self.beats {
            let (brightness, saturation) = try Self.measure(at: beat.at)
            #expect(
                abs(brightness - beat.brightness) <= Self.brightnessTolerance,
                Comment(rawValue: "at \(beat.at)s the frame is "
                    + String(format: "%.2f", brightness) + " bright, the reference \(beat.brightness)")
            )
            #expect(
                abs(saturation - beat.saturation) <= Self.saturationTolerance,
                Comment(rawValue: "at \(beat.at)s the frame carries "
                    + String(format: "%.2f", saturation) + " colour, the reference \(beat.saturation)")
            )
        }
    }

    private static func measure(at elapsed: TimeInterval) throws -> (brightness: Double, saturation: Double) {
        let controller = LinkstartOverlayController()
        controller.pinForOffscreenRender(elapsed: elapsed)
        let renderer = ImageRenderer(
            content: LinkstartView(controller: controller, showsDetail: true)
                .frame(width: 800, height: 500)
        )
        renderer.scale = 1
        let image = try #require(renderer.nsImage)
        let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))

        var brightness = 0.0
        var saturation = 0.0
        var samples = 0.0
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 5) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 5) {
                guard let colour = bitmap.colorAt(x: x, y: y) else { continue }
                let red = colour.redComponent, green = colour.greenComponent, blue = colour.blueComponent
                brightness += (red + green + blue) / 3
                saturation += max(red, green, blue) - min(red, green, blue)
                samples += 1
            }
        }
        guard samples > 0 else { return (0, 0) }
        return (brightness / samples, saturation / samples)
    }
}
