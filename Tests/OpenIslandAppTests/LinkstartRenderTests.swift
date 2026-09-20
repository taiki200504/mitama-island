import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Renders the login sequence offscreen at a few moments and writes the PNGs
/// out for a human to look at.
///
/// The screenshot harness cannot answer "does this look right" while the
/// display is asleep — the capture comes back a single flat black — and a
/// long build is exactly the thing that finishes after the screen has gone
/// off. `ImageRenderer` needs no window, no screen and no focus, so the
/// pictures are the same at three in the morning as at noon.
///
/// Set `OPEN_ISLAND_RENDER_DIR` to collect them; without it the test still
/// runs and only asserts that each frame has real content.
@MainActor
struct LinkstartRenderTests {
    /// Every beat of the sequence, and what it should be: `flat` marks the
    /// moments the reference itself is one colour — the dark before the light,
    /// the white-out, the fade at the end — so an empty frame there is the
    /// right answer rather than the bug this test is looking for.
    private struct Moment {
        let at: TimeInterval
        let flat: Bool

        init(_ at: TimeInterval, flat: Bool = false) {
            self.at = at
            self.flat = flat
        }
    }

    private static let moments: [Moment] = [
        Moment(0.7, flat: true),    // dark, before anything
        Moment(2.4),                // the speck
        Moment(4.2),                // the tunnel
        Moment(5.4, flat: true),    // the white-out
        Moment(7.0),                // the interface
        Moment(8.8),                // the checks
        Moment(10.2),               // language
        Moment(11.6),               // sign-in
        Moment(13.0),               // the confirmation
        Moment(15.0),               // welcome
        Moment(17.4),               // the dive
        Moment(18.7, flat: true),   // white, the end
    ]

    @Test
    func everyBeatOfTheSequenceDrawsSomething() throws {
        let directory = ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_DIR"]
        if let directory {
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }

        for moment in Self.moments {
            let elapsed = moment.at
            let controller = LinkstartOverlayController()
            controller.pinForOffscreenRender(elapsed: elapsed)
            let view = LinkstartView(controller: controller, showsDetail: true)
                .frame(width: 1_200, height: 750)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let image = try #require(renderer.nsImage, "no image at \(elapsed)s")

            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff) else {
                Issue.record("could not read back the frame at \(elapsed)s")
                continue
            }

            // A frame of one flat colour is the failure this test exists to
            // catch: it is what a black capture, an empty canvas or a view
            // that drew nothing all look like.
            var seen = Set<UInt32>()
            // Every 8 px: the first beat is a speck of colour in the middle
            // of a white field, and a 40 px grid walks straight past it.
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 8) {
                for y in stride(from: 0, to: bitmap.pixelsHigh, by: 8) {
                    guard let colour = bitmap.colorAt(x: x, y: y) else { continue }
                    let key = UInt32(colour.redComponent * 255) << 16
                        | UInt32(colour.greenComponent * 255) << 8
                        | UInt32(colour.blueComponent * 255)
                    seen.insert(key)
                }
            }
            if moment.flat {
                #expect(seen.count <= 3, "the frame at \(elapsed)s should be one flat colour")
            } else {
                #expect(seen.count > 3, "the frame at \(elapsed)s is a flat fill")
            }

            if let directory, let png = bitmap.representation(using: .png, properties: [:]) {
                let name = String(format: "linkstart-%.1fs.png", elapsed)
                try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
            }
        }
    }
}
