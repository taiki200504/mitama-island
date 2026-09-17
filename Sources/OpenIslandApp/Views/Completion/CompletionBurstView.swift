import OpenIslandCore
import SwiftUI

/// The light thrown out of the notch as a session completes, drawn from
/// `CompletionBurst`. The burst origin is the top centre of this view — the
/// bottom edge of the notch.
struct CompletionBurstView: View {
    let startedAt: Date
    let accent: Color

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            Canvas { canvas, size in
                Self.draw(elapsed: elapsed, accent: accent, in: &canvas, size: size)
            }
        }
        .allowsHitTesting(false)
    }

    private static func draw(elapsed: TimeInterval, accent: Color, in canvas: inout GraphicsContext, size: CGSize) {
        let origin = CGPoint(x: size.width / 2, y: 0)
        let reach = min(size.width / 2, size.height)
        canvas.blendMode = .plusLighter

        let flare = CompletionBurst.flare(at: elapsed)
        if flare.opacity > 0 {
            let halfWidth = size.width / 2 * flare.width
            let rect = CGRect(x: origin.x - halfWidth, y: 0, width: halfWidth * 2, height: 3)
            canvas.fill(
                Path(roundedRect: rect, cornerRadius: 1.5),
                with: .linearGradient(
                    Gradient(colors: [.clear, accent.opacity(flare.opacity), .white.opacity(flare.opacity), accent.opacity(flare.opacity), .clear]),
                    startPoint: CGPoint(x: rect.minX, y: 0),
                    endPoint: CGPoint(x: rect.maxX, y: 0)
                )
            )
        }

        for ring in CompletionBurst.rings(at: elapsed) {
            // Wide and shallow: a wave spreading along under the menu bar
            // rather than a circle dropping into the work area.
            let rx = reach * ring.radius
            let ry = rx * 0.32
            let rect = CGRect(x: origin.x - rx, y: -ry, width: rx * 2, height: ry * 2)
            canvas.stroke(Path(ellipseIn: rect), with: .color(accent.opacity(ring.opacity)), lineWidth: 2)
        }

        for shard in CompletionBurst.shards(at: elapsed) where shard.opacity > 0.01 {
            let centre = CGPoint(x: origin.x + shard.x * reach, y: origin.y + shard.y * reach * 0.6)
            let half = shard.size / 2
            var diamond = Path()
            diamond.move(to: CGPoint(x: 0, y: -half))
            diamond.addLine(to: CGPoint(x: half * 0.6, y: 0))
            diamond.addLine(to: CGPoint(x: 0, y: half))
            diamond.addLine(to: CGPoint(x: -half * 0.6, y: 0))
            diamond.closeSubpath()
            let placed = diamond
                .applying(CGAffineTransform(rotationAngle: shard.rotationDegrees * .pi / 180))
                .applying(CGAffineTransform(translationX: centre.x, y: centre.y))
            let colour = shard.isAccent ? accent : .white
            canvas.fill(placed, with: .color(colour.opacity(shard.opacity)))
        }
    }
}
