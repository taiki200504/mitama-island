import AppKit

/// Renders a templated menu bar icon with state-dependent styling.
///
/// The icon uses SAO-inspired geometry to match the app's visual language.
/// State is conveyed through subtle changes to convey at-a-glance information:
/// - idle: outline only
/// - waiting: outline + center dot
/// - running: outline + center dot + indicator
/// - approvalNeeded: filled solid (hand-actionable state)
public enum MenuBarIconRenderer {
    /// Menu bar icon state reflects the primary action needed.
    public enum State: Equatable {
        case idle
        case waiting
        case running
        case approvalNeeded
    }

    /// Renders the menu bar icon for the given state.
    ///
    /// Returns an NSImage configured as a template, so it respects light/dark
    /// appearance and remains accessible on any menu bar background.
    ///
    /// - Parameter state: The current island state.
    /// - Returns: An NSImage with `isTemplate = true`, sized for menu bar display.
    public static func image(for state: State) -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            drawIcon(in: rect, state: state)
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Private rendering

    private static func drawIcon(in rect: CGRect, state: State) {
        let ink = NSColor(white: 0, alpha: 1)
        ink.setStroke()
        ink.setFill()

        // Island bounds: wide and shallow to match the notch
        let islandRect = CGRect(x: 1.5, y: 4.6, width: 15, height: 8)
        let centerPoint = CGPoint(x: islandRect.midX, y: islandRect.midY)

        // Draw the characteristic island outline (notch shape: flat top, rounded bottom)
        let outlinePath = notchPath(islandRect)
        outlinePath.lineWidth = 1.4

        switch state {
        case .idle:
            // Outline only
            outlinePath.stroke()

        case .waiting:
            // Outline + center dot
            outlinePath.stroke()
            dotPath(at: centerPoint, radius: 1.6).fill()

        case .running:
            // Outline + center dot + outer indicator for motion sense
            outlinePath.stroke()
            dotPath(at: centerPoint, radius: 1.6).fill()
            // Small indicator at top-right
            let indicatorPoint = CGPoint(x: islandRect.maxX - 2.5, y: islandRect.minY + 1.5)
            dotPath(at: indicatorPoint, radius: 0.8).fill()

        case .approvalNeeded:
            // Solid fill (hand-actionable) — windingRule creates filled effect
            let filled = NSBezierPath()
            filled.append(outlinePath)
            filled.append(dotPath(at: centerPoint, radius: 1.8))
            filled.windingRule = .evenOdd
            filled.fill()
        }
    }

    /// Creates the characteristic island outline: flat top, rounded bottom.
    /// Matches the visual language of the main island.
    private static func notchPath(_ rect: CGRect) -> NSBezierPath {
        let path = NSBezierPath()
        let radius: CGFloat = 3

        // Start at bottom-left, go clockwise
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        // Up to top-left radius start
        path.line(to: CGPoint(x: rect.minX, y: rect.minY + radius))

        // Top-left corner arc (rounded)
        path.appendArc(
            withCenter: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
            radius: radius,
            startAngle: 180,
            endAngle: 270
        )

        // Top edge (flat)
        path.line(to: CGPoint(x: rect.maxX - radius, y: rect.minY))

        // Top-right corner arc (rounded)
        path.appendArc(
            withCenter: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
            radius: radius,
            startAngle: 270,
            endAngle: 360
        )

        // Right edge (down to bottom)
        path.line(to: CGPoint(x: rect.maxX, y: rect.maxY))

        // Close path
        path.close()

        return path
    }

    /// Creates a circular dot at the given center point.
    private static func dotPath(at center: CGPoint, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
    }
}
