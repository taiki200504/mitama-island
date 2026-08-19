import Foundation

/// Where the hand is pointing, and whether it is pinching.
///
/// `TwoFingerPoseDetector` and `SwipeDetector` answer "did a gesture happen".
/// This answers "where is the hand right now, and is it holding something" —
/// the two halves of pointing at a menu item and picking it.
public struct FingerCursorReading: Equatable, Sendable {
    /// Index fingertip, in Vision's normalized bottom-left-origin space.
    public var position: HandLandmarks.Point
    /// Thumb-to-index distance divided by hand span. Scale free, so moving the
    /// hand closer to the camera does not read as a pinch.
    public var pinchRatio: Double
    /// Index-to-little spread over hand span. An open hand reads high, a fist low.
    public var spreadRatio: Double

    public init(position: HandLandmarks.Point, pinchRatio: Double, spreadRatio: Double) {
        self.position = position
        self.pinchRatio = pinchRatio
        self.spreadRatio = spreadRatio
    }
}

/// Turns landmarks into a cursor reading.
///
/// Every distance is divided by the wrist-to-middle-knuckle span. Raw distances
/// look identical for "a small hand pinching" and "a large hand held far away",
/// so an absolute threshold would fire on whichever the camera happened to see.
public struct FingerCursorDetector: Equatable, Sendable {
    public struct Configuration: Equatable, Sendable {
        public var minimumConfidence: Double
        /// Below this span the hand is too small in frame to measure reliably.
        public var minimumPalmAxisLength: Double

        public init(minimumConfidence: Double = 0.3, minimumPalmAxisLength: Double = 0.04) {
            self.minimumConfidence = minimumConfidence
            self.minimumPalmAxisLength = minimumPalmAxisLength
        }
    }

    public var configuration: Configuration

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    public func reading(from landmarks: HandLandmarks) -> FingerCursorReading? {
        let points = [
            landmarks.wrist,
            landmarks.thumb.tip,
            landmarks.index.tip,
            landmarks.middle.metacarpophalangeal,
            landmarks.little.tip,
        ]
        guard points.allSatisfy({ $0.confidence >= configuration.minimumConfidence }) else { return nil }

        let span = distance(landmarks.wrist, landmarks.middle.metacarpophalangeal)
        guard span >= configuration.minimumPalmAxisLength else { return nil }

        return FingerCursorReading(
            position: landmarks.index.tip,
            pinchRatio: distance(landmarks.thumb.tip, landmarks.index.tip) / span,
            spreadRatio: distance(landmarks.index.tip, landmarks.little.tip) / span
        )
    }
}

/// Pinch as a held state, not an instant.
///
/// Two thresholds rather than one: fingers hover around any single value while
/// the hand is still, which would emit a stream of began/ended pairs. Closing
/// past `enter` starts the pinch; only opening past the wider `exit` ends it.
public struct PinchLatch: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        case began
        case ended
    }

    public struct Configuration: Equatable, Sendable {
        public var enterRatio: Double
        public var exitRatio: Double
        /// A pinch must persist this long before it counts. Fingers cross paths
        /// during ordinary movement; without this every wave would click.
        public var minimumHold: TimeInterval

        public init(enterRatio: Double = 0.35, exitRatio: Double = 0.50, minimumHold: TimeInterval = 0.08) {
            self.enterRatio = enterRatio
            self.exitRatio = exitRatio
            self.minimumHold = minimumHold
        }
    }

    public var configuration: Configuration
    private var closedSince: TimeInterval?
    private var isPinching = false

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    /// Feed one frame. Returns an event only on the transitions.
    public mutating func push(pinchRatio: Double, timestamp: TimeInterval) -> Event? {
        if isPinching {
            guard pinchRatio > configuration.exitRatio else { return nil }
            isPinching = false
            closedSince = nil
            return .ended
        }

        guard pinchRatio <= configuration.enterRatio else {
            closedSince = nil
            return nil
        }

        guard let since = closedSince else {
            closedSince = timestamp
            return nil
        }

        guard timestamp - since >= configuration.minimumHold else { return nil }
        isPinching = true
        return .began
    }

    /// Drop the held state without emitting. Use when the hand leaves the frame —
    /// otherwise the next hand that appears inherits a pinch it never made.
    public mutating func reset() {
        isPinching = false
        closedSince = nil
    }

    public var isHolding: Bool { isPinching }
}

private func distance(_ a: HandLandmarks.Point, _ b: HandLandmarks.Point) -> Double {
    let dx = a.x - b.x
    let dy = a.y - b.y
    return (dx * dx + dy * dy).squareRoot()
}


/// Turns "where the hand is" into "which row it means".
///
/// A hand in front of a laptop covers the middle of the camera's view and not
/// much else — reaching the top and bottom of frame means standing up. So the
/// list is spread across the band a seated hand can actually reach, and
/// anything beyond it counts as the end of the list rather than as nothing.
public enum FingerAim: Sendable {
    /// Vision's y runs bottom-up, so this reads: from a little below centre to
    /// a little above it.
    public static let reachableBand: ClosedRange<Double> = 0.30...0.70

    /// Row index from the top, or `nil` when there is nothing to aim at.
    public static func rowIndex(normalizedY y: Double, rowCount: Int) -> Int? {
        guard rowCount > 0 else { return nil }
        guard rowCount > 1 else { return 0 }

        let clamped = min(max(y, reachableBand.lowerBound), reachableBand.upperBound)
        let span = reachableBand.upperBound - reachableBand.lowerBound
        // A high hand means the top of the list, and the top of the list is
        // index zero.
        let fromTop = (reachableBand.upperBound - clamped) / span
        let index = Int(fromTop * Double(rowCount))
        return min(rowCount - 1, max(0, index))
    }
}
