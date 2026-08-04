import Foundation

/// Whether a usage figure counts up or counts down.
///
/// The same number answers two different questions. "72%" tells you what you
/// have spent; "28% left" tells you what you have to work with. People reach for
/// one or the other, so it is a choice rather than a default.
public enum UsageValueMode: String, CaseIterable, Identifiable, Sendable {
    case used
    case remaining

    public var id: String { rawValue }
    public var labelKey: String { "settings.usage.valueMode.\(rawValue)" }

    /// The figure to show, 0–100, given how much of the window is spent.
    public func displayedPercentage(used: Double) -> Double {
        switch self {
        case .used: max(0, min(100, used))
        case .remaining: max(0, min(100, 100 - used))
        }
    }

    /// Colour follows the *pressure*, not the printed number: 90% used and
    /// 10% remaining are the same situation and must look the same.
    public func pressure(used: Double) -> Double { max(0, min(100, used)) }
}

/// Decides when to warn that a usage window is running out.
///
/// Pure on purpose: "did we already warn about this window" is the whole
/// difficulty, and a monitor that re-warns every refresh is worse than none.
public struct UsageThresholdMonitor: Equatable, Sendable {
    /// Percentage used at which to warn. Zero means never.
    public var threshold: Int
    /// Identifiers of windows already warned about, so each fires once.
    public private(set) var alerted: Set<String>

    public init(threshold: Int, alerted: Set<String> = []) {
        self.threshold = threshold
        self.alerted = alerted
    }

    public struct Window: Equatable, Sendable {
        public var id: String
        public var label: String
        public var usedPercentage: Double
        /// Distinguishes one five-hour window from the next. Two windows with
        /// the same label but different reset times are different windows, and
        /// each deserves its own warning.
        public var resetsAt: Date?

        public init(id: String, label: String, usedPercentage: Double, resetsAt: Date?) {
            self.id = id
            self.label = label
            self.usedPercentage = usedPercentage
            self.resetsAt = resetsAt
        }

        var alertKey: String {
            let reset = resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "none"
            return "\(id)|\(label)|\(reset)"
        }
    }

    /// Returns the windows that crossed the threshold since the last call, and
    /// records them so they do not fire again.
    public mutating func crossings(in windows: [Window]) -> [Window] {
        guard threshold > 0 else { return [] }
        let live = Set(windows.map(\.alertKey))
        // Forget windows that have rolled over, so the next five-hour window can
        // warn again without the set growing forever.
        alerted.formIntersection(live)

        var fired: [Window] = []
        for window in windows where window.usedPercentage >= Double(threshold) {
            guard !alerted.contains(window.alertKey) else { continue }
            alerted.insert(window.alertKey)
            fired.append(window)
        }
        return fired
    }
}
