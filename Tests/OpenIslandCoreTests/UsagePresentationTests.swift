import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Usage value mode")
struct UsageValueModeTests {
    @Test("Used counts up, remaining counts down")
    func complementary() {
        #expect(UsageValueMode.used.displayedPercentage(used: 72) == 72)
        #expect(UsageValueMode.remaining.displayedPercentage(used: 72) == 28)
    }

    /// The bug this prevents: colouring "10% left" green because the printed
    /// number is small, when the user is in fact almost out.
    @Test("Pressure ignores which way the figure is written")
    func pressureIsIndependentOfMode() {
        for mode in UsageValueMode.allCases {
            #expect(mode.pressure(used: 92) == 92)
        }
    }

    @Test("Values outside 0-100 are clamped")
    func clamps() {
        #expect(UsageValueMode.used.displayedPercentage(used: 140) == 100)
        #expect(UsageValueMode.remaining.displayedPercentage(used: 140) == 0)
        #expect(UsageValueMode.remaining.displayedPercentage(used: -5) == 100)
    }
}

@Suite("Usage threshold monitor")
struct UsageThresholdMonitorTests {
    private func window(_ used: Double, resetsAt: Date? = nil) -> UsageThresholdMonitor.Window {
        .init(id: "claude", label: "5h", usedPercentage: used, resetsAt: resetsAt)
    }

    @Test("A threshold of zero never fires")
    func offByDefault() {
        var monitor = UsageThresholdMonitor(threshold: 0)
        #expect(monitor.crossings(in: [window(99)]).isEmpty)
    }

    @Test("Crossing the threshold fires once")
    func firesOnce() {
        var monitor = UsageThresholdMonitor(threshold: 80)
        let reset = Date(timeIntervalSince1970: 1_000_000)
        #expect(monitor.crossings(in: [window(85, resetsAt: reset)]).count == 1)
        // The same window, still over — no second warning.
        #expect(monitor.crossings(in: [window(90, resetsAt: reset)]).isEmpty)
    }

    @Test("Below the threshold nothing fires")
    func staysQuietBelow() {
        var monitor = UsageThresholdMonitor(threshold: 80)
        #expect(monitor.crossings(in: [window(79)]).isEmpty)
        #expect(monitor.crossings(in: [window(80)]).count == 1)
    }

    /// The next five-hour window is a different window even though its label is
    /// identical, so it must be able to warn again.
    @Test("A window that rolls over warns again")
    func newWindowWarnsAgain() {
        var monitor = UsageThresholdMonitor(threshold: 80)
        let first = Date(timeIntervalSince1970: 1_000_000)
        let second = Date(timeIntervalSince1970: 1_018_000)
        #expect(monitor.crossings(in: [window(85, resetsAt: first)]).count == 1)
        #expect(monitor.crossings(in: [window(85, resetsAt: second)]).count == 1)
    }

    /// Without this the set would grow for every window the app ever saw.
    @Test("Windows that disappear are forgotten")
    func forgetsStaleWindows() {
        var monitor = UsageThresholdMonitor(threshold: 80)
        let reset = Date(timeIntervalSince1970: 1_000_000)
        _ = monitor.crossings(in: [window(85, resetsAt: reset)])
        #expect(monitor.alerted.count == 1)
        _ = monitor.crossings(in: [])
        #expect(monitor.alerted.isEmpty)
    }

    @Test("Each provider's windows warn separately")
    func perProvider() {
        var monitor = UsageThresholdMonitor(threshold: 80)
        let fired = monitor.crossings(in: [
            .init(id: "claude", label: "5h", usedPercentage: 85, resetsAt: nil),
            .init(id: "codex", label: "5h", usedPercentage: 85, resetsAt: nil)
        ])
        #expect(fired.count == 2)
    }
}
