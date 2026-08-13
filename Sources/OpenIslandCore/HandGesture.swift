import Foundation

/// Landmark positions kept in Vision's normalized, bottom-left-origin coordinate system.
public struct HandLandmarks: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var confidence: Double

        public init(x: Double, y: Double, confidence: Double) {
            self.x = x
            self.y = y
            self.confidence = confidence
        }
    }

    public struct Thumb: Equatable, Sendable {
        public var carpometacarpal: Point
        public var metacarpophalangeal: Point
        public var interphalangeal: Point
        public var tip: Point

        public init(carpometacarpal: Point, metacarpophalangeal: Point, interphalangeal: Point, tip: Point) {
            self.carpometacarpal = carpometacarpal
            self.metacarpophalangeal = metacarpophalangeal
            self.interphalangeal = interphalangeal
            self.tip = tip
        }
    }

    public struct Finger: Equatable, Sendable {
        public var metacarpophalangeal: Point
        public var proximalInterphalangeal: Point
        public var distalInterphalangeal: Point
        public var tip: Point

        public init(metacarpophalangeal: Point, proximalInterphalangeal: Point, distalInterphalangeal: Point, tip: Point) {
            self.metacarpophalangeal = metacarpophalangeal
            self.proximalInterphalangeal = proximalInterphalangeal
            self.distalInterphalangeal = distalInterphalangeal
            self.tip = tip
        }
    }

    public var wrist: Point
    public var thumb: Thumb
    public var index: Finger
    public var middle: Finger
    public var ring: Finger
    public var little: Finger

    public init(wrist: Point, thumb: Thumb, index: Finger, middle: Finger, ring: Finger, little: Finger) {
        self.wrist = wrist
        self.thumb = thumb
        self.index = index
        self.middle = middle
        self.ring = ring
        self.little = little
    }
}

/// Classifies the pose without importing Vision so camera delivery stays outside Core.
public struct TwoFingerPoseDetector: Equatable, Sendable {
    public struct Configuration: Equatable, Sendable {
        public var minimumConfidence: Double
        public var minimumExtendedProjection: Double
        public var maximumFoldedProjection: Double
        public var minimumPalmAxisLength: Double

        public init(
            minimumConfidence: Double = 0.3,
            minimumExtendedProjection: Double = 0.08,
            maximumFoldedProjection: Double = 0.055,
            minimumPalmAxisLength: Double = 0.04
        ) {
            self.minimumConfidence = minimumConfidence
            self.minimumExtendedProjection = minimumExtendedProjection
            self.maximumFoldedProjection = maximumFoldedProjection
            self.minimumPalmAxisLength = minimumPalmAxisLength
        }
    }

    public var configuration: Configuration

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    public func isRecognized(in landmarks: HandLandmarks) -> Bool {
        guard landmarks.allPoints.allSatisfy({ $0.confidence >= configuration.minimumConfidence }) else {
            return false
        }

        // The hand's own wrist-to-knuckle axis keeps a rotated hand from being
        // judged against the camera's vertical axis.
        let knuckleCenter = average([
            landmarks.index.metacarpophalangeal,
            landmarks.middle.metacarpophalangeal,
            landmarks.ring.metacarpophalangeal,
            landmarks.little.metacarpophalangeal,
        ])
        let palmAxis = vector(from: landmarks.wrist, to: knuckleCenter)
        let palmAxisLength = length(palmAxis)
        guard palmAxisLength >= configuration.minimumPalmAxisLength else { return false }
        let unitPalmAxis = (x: palmAxis.x / palmAxisLength, y: palmAxis.y / palmAxisLength)

        return isExtended(landmarks.index, along: unitPalmAxis)
            && isExtended(landmarks.middle, along: unitPalmAxis)
            && isFolded(landmarks.ring, along: unitPalmAxis)
            && isFolded(landmarks.little, along: unitPalmAxis)
    }

    /// The midpoint reduces individual fingertip jitter before it reaches the swipe detector.
    public func representativeTipPosition(in landmarks: HandLandmarks) -> HandLandmarks.Point? {
        guard isRecognized(in: landmarks) else { return nil }
        return average([landmarks.index.tip, landmarks.middle.tip])
    }

    private func isExtended(_ finger: HandLandmarks.Finger, along axis: (x: Double, y: Double)) -> Bool {
        projection(vector(from: finger.metacarpophalangeal, to: finger.tip), onto: axis)
            >= configuration.minimumExtendedProjection
    }

    private func isFolded(_ finger: HandLandmarks.Finger, along axis: (x: Double, y: Double)) -> Bool {
        projection(vector(from: finger.metacarpophalangeal, to: finger.tip), onto: axis)
            <= configuration.maximumFoldedProjection
    }
}

/// Classifies the open hand — every finger extended, held still.
///
/// Deliberately exclusive with `TwoFingerPoseDetector`: that one requires the
/// ring and little fingers to be folded, this one requires them extended. A
/// swipe can never be mistaken for a raised palm, so the two gestures can watch
/// the same camera frames without stealing from each other.
public struct OpenPalmDetector: Equatable, Sendable {
    public struct Configuration: Equatable, Sendable {
        public var minimumConfidence: Double
        public var minimumExtendedProjection: Double
        public var minimumPalmAxisLength: Double

        public init(
            minimumConfidence: Double = 0.3,
            minimumExtendedProjection: Double = 0.08,
            minimumPalmAxisLength: Double = 0.04
        ) {
            self.minimumConfidence = minimumConfidence
            self.minimumExtendedProjection = minimumExtendedProjection
            self.minimumPalmAxisLength = minimumPalmAxisLength
        }
    }

    public var configuration: Configuration

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    /// The thumb is left out on purpose: it leaves the palm sideways rather than
    /// along the wrist-to-knuckle axis, so measuring it the same way as the
    /// others would reject perfectly ordinary open hands.
    public func isRecognized(in landmarks: HandLandmarks) -> Bool {
        guard landmarks.allPoints.allSatisfy({ $0.confidence >= configuration.minimumConfidence }) else {
            return false
        }

        let knuckleCenter = average([
            landmarks.index.metacarpophalangeal,
            landmarks.middle.metacarpophalangeal,
            landmarks.ring.metacarpophalangeal,
            landmarks.little.metacarpophalangeal,
        ])
        let palmAxis = vector(from: landmarks.wrist, to: knuckleCenter)
        let palmAxisLength = length(palmAxis)
        guard palmAxisLength >= configuration.minimumPalmAxisLength else { return false }
        let unitPalmAxis = (x: palmAxis.x / palmAxisLength, y: palmAxis.y / palmAxisLength)

        return [landmarks.index, landmarks.middle, landmarks.ring, landmarks.little].allSatisfy { finger in
            projection(vector(from: finger.metacarpophalangeal, to: finger.tip), onto: unitPalmAxis)
                >= configuration.minimumExtendedProjection
        }
    }
}

/// Fires once when a pose has been held for long enough to be deliberate.
///
/// A pose that fired the moment it was recognised would go off while the hand
/// is on its way somewhere else. Holding is the part that carries intent, and
/// it is also what keeps this from firing again every frame afterwards.
public struct PoseHoldDetector: Equatable, Sendable {
    public struct Configuration: Equatable, Sendable {
        public var minimumHoldDuration: TimeInterval
        public var cooldownDuration: TimeInterval

        public init(
            minimumHoldDuration: TimeInterval = 0.6,
            cooldownDuration: TimeInterval = 2.0
        ) {
            self.minimumHoldDuration = minimumHoldDuration
            self.cooldownDuration = cooldownDuration
        }
    }

    public var configuration: Configuration

    private var holdStartedAt: TimeInterval?
    private var lastFiredAt: TimeInterval?

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    /// Returns true on the single frame where the hold becomes long enough.
    public mutating func push(isPosed: Bool, timestamp: TimeInterval) -> Bool {
        guard isPosed else {
            holdStartedAt = nil
            return false
        }

        if let lastFiredAt, timestamp - lastFiredAt < configuration.cooldownDuration {
            // Still inside the cooldown. The hand is usually still up at this
            // point, so the hold must not start counting again yet.
            return false
        }

        guard let startedAt = holdStartedAt else {
            holdStartedAt = timestamp
            return false
        }

        guard timestamp - startedAt >= configuration.minimumHoldDuration else { return false }
        holdStartedAt = nil
        lastFiredAt = timestamp
        return true
    }
}

/// Which way a swipe travelled, in the real world rather than in Vision's
/// bottom-left coordinate system.
public enum SwipeDirection: Equatable, Sendable {
    case down
    case up
}

/// Detects one deliberate vertical swipe from a bounded run of valid hand-pose frames.
public struct SwipeDetector: Equatable, Sendable {
    public struct Configuration: Equatable, Sendable {
        public var minimumConsecutiveFrames: Int
        public var minimumDistance: Double
        public var minimumDuration: TimeInterval
        public var maximumDuration: TimeInterval
        public var minimumVerticalDominance: Double
        public var cooldownDuration: TimeInterval
        public var maximumBufferedObservations: Int

        public init(
            minimumConsecutiveFrames: Int = 3,
            minimumDistance: Double = 0.15,
            minimumDuration: TimeInterval = 0.15,
            maximumDuration: TimeInterval = 1.0,
            minimumVerticalDominance: Double = 0.8,
            cooldownDuration: TimeInterval = 1.0,
            maximumBufferedObservations: Int = 30
        ) {
            self.minimumConsecutiveFrames = minimumConsecutiveFrames
            self.minimumDistance = minimumDistance
            self.minimumDuration = minimumDuration
            self.maximumDuration = maximumDuration
            self.minimumVerticalDominance = minimumVerticalDominance
            self.cooldownDuration = cooldownDuration
            self.maximumBufferedObservations = maximumBufferedObservations
        }
    }

    private struct Observation: Equatable, Sendable {
        var position: HandLandmarks.Point
        var timestamp: TimeInterval
    }

    public var configuration: Configuration
    private var observations: [Observation] = []
    private var lastRecognitionTimestamp: TimeInterval?

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    /// Reports a direction at most once per gesture; an invalid pose breaks
    /// continuity. Nil means "nothing yet", which is most frames.
    public mutating func push(
        isTwoFingerPose: Bool,
        representativeTipPosition: HandLandmarks.Point,
        timestamp: TimeInterval
    ) -> SwipeDirection? {
        guard isTwoFingerPose else {
            observations.removeAll(keepingCapacity: true)
            return nil
        }

        if let lastRecognitionTimestamp, timestamp - lastRecognitionTimestamp < configuration.cooldownDuration {
            observations.removeAll(keepingCapacity: true)
            return nil
        }

        guard observations.last.map({ timestamp > $0.timestamp }) ?? true else { return nil }
        observations.append(.init(position: representativeTipPosition, timestamp: timestamp))
        if observations.count > configuration.maximumBufferedObservations {
            observations.removeFirst(observations.count - configuration.maximumBufferedObservations)
        }

        guard observations.count >= configuration.minimumConsecutiveFrames else { return nil }
        for start in observations.dropLast().reversed() {
            let end = observations[observations.count - 1]
            let duration = end.timestamp - start.timestamp
            if duration > configuration.maximumDuration { break }
            guard duration >= configuration.minimumDuration,
                  let direction = swipeDirection(from: start, to: end) else { continue }

            lastRecognitionTimestamp = timestamp
            observations.removeAll(keepingCapacity: true)
            return direction
        }
        return nil
    }

    /// Vision's y grows upward, so a hand moving down the screen produces a
    /// falling y. Converting here keeps that inversion out of the caller.
    private func swipeDirection(from start: Observation, to end: Observation) -> SwipeDirection? {
        let movement = vector(from: start.position, to: end.position)
        let distance = length(movement)
        guard distance >= configuration.minimumDistance else { return nil }
        guard abs(movement.y) / distance >= configuration.minimumVerticalDominance else { return nil }
        return movement.y < 0 ? .down : .up
    }
}

private extension HandLandmarks {
    var allPoints: [Point] {
        [
            wrist,
            thumb.carpometacarpal, thumb.metacarpophalangeal, thumb.interphalangeal, thumb.tip,
            index.metacarpophalangeal, index.proximalInterphalangeal, index.distalInterphalangeal, index.tip,
            middle.metacarpophalangeal, middle.proximalInterphalangeal, middle.distalInterphalangeal, middle.tip,
            ring.metacarpophalangeal, ring.proximalInterphalangeal, ring.distalInterphalangeal, ring.tip,
            little.metacarpophalangeal, little.proximalInterphalangeal, little.distalInterphalangeal, little.tip,
        ]
    }
}

private func average(_ points: [HandLandmarks.Point]) -> HandLandmarks.Point {
    let count = Double(points.count)
    return .init(
        x: points.map(\.x).reduce(0, +) / count,
        y: points.map(\.y).reduce(0, +) / count,
        confidence: points.map(\.confidence).min() ?? 0
    )
}

private func vector(from start: HandLandmarks.Point, to end: HandLandmarks.Point) -> (x: Double, y: Double) {
    (x: end.x - start.x, y: end.y - start.y)
}

private func length(_ vector: (x: Double, y: Double)) -> Double {
    hypot(vector.x, vector.y)
}

private func projection(_ vector: (x: Double, y: Double), onto axis: (x: Double, y: Double)) -> Double {
    vector.x * axis.x + vector.y * axis.y
}
