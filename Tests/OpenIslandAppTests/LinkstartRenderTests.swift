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
    private static let moments: [TimeInterval] = [0.8, 2.4, 4.4, 6.0]

    @Test
    func everyBeatOfTheSequenceDrawsSomething() throws {
        let directory = ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_DIR"]
        if let directory {
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }

        for elapsed in Self.moments {
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
            #expect(seen.count > 3, "the frame at \(elapsed)s is a flat fill")

            if let directory, let png = bitmap.representation(using: .png, properties: [:]) {
                let name = String(format: "linkstart-%.1fs.png", elapsed)
                try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
            }
        }
    }
}
