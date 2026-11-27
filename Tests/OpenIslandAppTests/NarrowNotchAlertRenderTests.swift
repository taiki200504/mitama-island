import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// One offscreen frame of the narrow MacBook pill: a 150pt physical notch,
/// the 280pt outer cap, a 5-hour urgent warning, and three more waiting
/// behind it. `ImageRenderer` needs no window. Set `OPEN_ISLAND_RENDER_DIR`
/// to also write the PNG; without it the test only checks the frame.
@MainActor
struct NarrowNotchAlertRenderTests {
    private let physicalNotchWidth: CGFloat = 150
    private let configuredMaxWidth: CGFloat = 280
    private let height: CGFloat = 32

    @Test
    func narrowNotchRendersTheFiveHourAlertOnOneLine() throws {
        let peek = IslandPeekBand.Content(
            agent: IslandPeekBand.mitamaLabel,
            subject: .mitamaAlert,
            elapsed: .hours(5),
            othersWaiting: 3
        )
        let content = IslandClosedContent(body: .urgent(peek))
        let layout = V6ClosedPill.macbookLayout(
            content: content,
            sneakPeek: nil,
            rightSlot: nil,
            physicalNotchWidth: physicalNotchWidth,
            pad: height / 2,
            configuredMaxWidth: configuredMaxWidth
        )
        #expect(layout.compactBody)
        #expect(layout.outerWidth == configuredMaxWidth)

        let pill = V6ClosedPill(
            mode: .waiting,
            content: content,
            layout: .macbook,
            height: height,
            physicalNotchWidth: physicalNotchWidth,
            maxWidth: configuredMaxWidth
        )
        let renderer = ImageRenderer(content: pill)
        renderer.scale = 1
        let image = try #require(renderer.nsImage)
        #expect(image.size.width == configuredMaxWidth)
        #expect(image.size.height == height)

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            Issue.record("could not read back the narrow alert frame")
            return
        }
        #expect(bitmap.pixelsWide == Int(configuredMaxWidth))
        #expect(bitmap.pixelsHigh == Int(height))

        let side = Int((configuredMaxWidth - physicalNotchWidth) / 2)
        let notchStart = side
        let notchEnd = side + Int(physicalNotchWidth)
        let left = foreground(in: bitmap, x: 0..<side)
        let notch = foreground(in: bitmap, x: notchStart..<notchEnd)
        let right = foreground(in: bitmap, x: notchEnd..<bitmap.pixelsWide)

        #expect(left.count > 8, "the warning did not draw on the leading side")
        #expect(right.count > 8, "the 5-hour tail did not draw")
        #expect(notch.count == 0, "ink crossed the \(Int(physicalNotchWidth))pt notch")
        #expect(left.span <= 16, "the warning wrapped: \(left.span)px tall")
        #expect(right.span <= 16, "the 5-hour tail wrapped: \(right.span)px tall")

        if let directory = ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_DIR"] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("notch-150-alert-5h.png"))
        }
    }

    /// Light or coloured pixels on the dark pill. A second text line makes
    /// `span` jump past one 8pt row.
    private func foreground(
        in bitmap: NSBitmapImageRep,
        x range: Range<Int>
    ) -> (count: Int, span: Int) {
        var count = 0
        var minY = Int.max
        var maxY = Int.min
        for x in range {
            for y in 0..<bitmap.pixelsHigh {
                guard let colour = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      colour.alphaComponent > 0.9 else { continue }
                let red = colour.redComponent
                let green = colour.greenComponent
                let blue = colour.blueComponent
                let brightest = max(red, green, blue)
                let dullest = min(red, green, blue)
                guard brightest > 0.45 || brightest - dullest > 0.25 else { continue }
                count += 1
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        let span = count == 0 ? 0 : maxY - minY + 1
        return (count, span)
    }
}
