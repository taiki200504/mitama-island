import SwiftUI
import OpenIslandCore

@MainActor
enum IslandDesignPalette {
    /// Tool names in an activity line. Deliberately the same colour as the
    /// running-status tint so "this row is doing something" reads from one
    /// colour whether you look at the dot or the line.
    static var toolAccent: Color { IslandThemes.current.statusTints.running }

    /// The settings window used to reach for `.orange`, `.red` and `.blue`
    /// directly, so a theme switch left it looking like a different app bolted
    /// onto the island. These three names are what the rest of the app means by
    /// "something wants attention", "something is wrong" and "this is the one
    /// you picked" — the same vocabulary the island already uses for sessions.
    static var warning: Color { IslandThemes.current.statusTints.waitingForApproval }
    static var critical: Color { IslandThemes.current.statusTints.critical }
    static var selection: Color { IslandThemes.current.accent }
    /// The window's own background, matching the island's panel.
    static var surface: Color { IslandThemes.current.ink }

    @MainActor
    enum Status {
        static var waitingAggregate: Color { IslandThemes.current.statusTints.waitingAggregate }
        static var waitingForApproval: Color { IslandThemes.current.statusTints.waitingForApproval }
        static var waitingForAnswer: Color { IslandThemes.current.statusTints.waitingForAnswer }
        static var running: Color { IslandThemes.current.statusTints.running }
        static var completed: Color { IslandThemes.current.statusTints.completed }
        static var inactive: Color { V6Palette.paper.opacity(0.38) }
        static var idle: Color { V6Palette.paper.opacity(0.35) }

        static func tint(for phase: SessionPhase) -> Color {
            switch phase {
            case .waitingForApproval:
                waitingForApproval
            case .waitingForAnswer:
                waitingForAnswer
            case .running:
                running
            case .completed:
                completed
            }
        }

        static func tint(for phase: SessionPhase, presence: IslandSessionPresence) -> Color {
            if phase == .waitingForApproval || phase == .waitingForAnswer {
                return tint(for: phase)
            }

            switch presence {
            case .running:
                return running
            case .active:
                return completed
            case .inactive:
                return inactive
            }
        }
    }
}
