import SwiftUI

/// Pure geometry for `SAORingView`'s concentric pulse rings.
enum SAORing {
    /// One radius per ring. Ring `i` lags the leading ring's progress by
    /// `0.12 * i`, so the rings read as catching up to each other rather than
    /// moving as one rigid disc.
    static func radii(progress: Double, count: Int, maxRadius: CGFloat) -> [CGFloat] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let lag = 0.12 * Double(index)
            let ringProgress = min(max(progress - lag, 0), 1)
            return maxRadius * CGFloat(ringProgress)
        }
    }
}

/// A burst of `count` concentric rings expanding from the centre, each one
/// lagging the last — the "something just landed" pulse.
struct SAORingView: View {
    var progress: Double
    var count: Int = 5
    var tint: Color
    var lineWidth: CGFloat = 1.5

    var body: some View {
        Canvas { context, size in
            let maxRadius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for radius in SAORing.radii(progress: progress, count: count, maxRadius: maxRadius) where radius > 0 {
                let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(tint), lineWidth: lineWidth)
            }
        }
    }
}

/// Pure geometry for `SAORaysView`'s radiating burst.
enum SAORays {
    /// Endpoints of `count` rays from `center`, the whole set rotated
    /// `6° * progress` so the burst spins open instead of snapping into place.
    static func endpoints(progress: Double, count: Int, center: CGPoint, length: CGFloat) -> [CGPoint] {
        guard count > 0, length > 0 else { return [] }
        let rotation = Angle.degrees(6 * progress).radians
        return (0..<count).map { index in
            let angle = (2 * .pi * Double(index) / Double(count)) + rotation
            return CGPoint(
                x: center.x + length * CGFloat(cos(angle)),
                y: center.y + length * CGFloat(sin(angle))
            )
        }
    }
}

/// 24 rays radiating from the centre, growing from nothing to 1.4× the
/// view's own diagonal as `progress` runs 0…1.
struct SAORaysView: View {
    var progress: Double
    var count: Int = 24
    var tint: Color

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let diagonal = (size.width * size.width + size.height * size.height).squareRoot()
            let length = diagonal * 1.4 * CGFloat(min(max(progress, 0), 1))
            guard length > 0 else { return }

            var path = Path()
            for point in SAORays.endpoints(progress: progress, count: count, center: center, length: length) {
                path.move(to: center)
                path.addLine(to: point)
            }
            context.stroke(path, with: .color(tint), lineWidth: 1)
        }
    }
}
