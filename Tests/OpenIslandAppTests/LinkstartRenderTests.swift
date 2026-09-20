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
        /// 外から時刻を渡されたときは、どこが白でどこが絵なのかを知って
        /// いるのは渡した人だけなので、平坦かどうかは判定しない。
        let asserts: Bool

        init(_ at: TimeInterval, flat: Bool = false, asserts: Bool = true) {
            self.at = at
            self.flat = flat
            self.asserts = asserts
        }
    }

    /// Every 0.6s across the whole sequence, so a beat that goes blank in
    /// the middle is caught instead of being found by eye later, plus the
    /// moments the reference itself changes during the senses (5.7-9.3s),
    /// where a 0.6s grid walks straight past discs that live for under a
    /// second. The flat ones are the reference's own empty frames: the dark
    /// it opens on, the white-out, the gap between two discs at 6.85, the
    /// one after the last disc leaves, the white before the language button,
    /// and the fade at the end.
    private static let builtInMoments: [Moment] = [
        Moment(0.2, flat: true),
        Moment(0.8, flat: true),
        Moment(1.4, flat: true),
        Moment(2.0),
        Moment(2.6),
        Moment(3.2),
        Moment(3.8),
        Moment(4.4),
        Moment(5.0, flat: true),
        // 5.6 は真っ白ではない: 参照でもここに確認の印が 2 つ、中央に
        // 小さく出ている（測ると彩度 0.003 の、ほとんど白い画面）。
        Moment(5.6),
        Moment(5.75),
        Moment(6.0),
        Moment(6.2),
        Moment(6.25),
        Moment(6.5),
        Moment(6.85),
        Moment(7.25),
        Moment(7.4),
        Moment(7.5),
        Moment(7.75),
        Moment(8.0),
        Moment(8.15),
        Moment(8.45),
        Moment(8.6),
        Moment(8.75),
        Moment(9.0, flat: true),
        Moment(9.2, flat: true),
        Moment(9.3),
        Moment(9.8),
        Moment(10.4),
        Moment(11.0),
        Moment(11.6),
        Moment(12.2),
        Moment(12.8),
        Moment(13.4),
        Moment(14.0),
        Moment(14.6),
        Moment(15.2),
        Moment(15.8),
        Moment(16.4),
        Moment(17.0),
        Moment(17.6),
        Moment(18.2),
        Moment(18.8, flat: true),
    ]

    /// 参照と突き合わせるときは、見たい時刻を 0.05 秒刻みで渡せた方が早い。
    /// `OPEN_ISLAND_RENDER_TIMES=5.75,6.25,6.85` のように並べる。
    private static var moments: [Moment] {
        guard let raw = ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_TIMES"] else {
            return builtInMoments
        }
        let times = raw.split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return times.isEmpty ? builtInMoments : times.map { Moment($0, asserts: false) }
    }

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
            if !moment.asserts {
                // 時刻を外から渡されたぶんは、書き出すだけ。
            } else if moment.flat {
                #expect(seen.count <= 3, "the frame at \(elapsed)s should be one flat colour")
            } else {
                #expect(seen.count > 3, "the frame at \(elapsed)s is a flat fill")
            }

            if let directory, let png = bitmap.representation(using: .png, properties: [:]) {
                let name = String(format: "linkstart-%gs.png", elapsed)
                try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
            }
        }
    }
}
