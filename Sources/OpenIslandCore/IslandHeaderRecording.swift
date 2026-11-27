import Foundation

/// Header microphone: stop island earshot when it is on; otherwise hand off to the Mac mitama app.
public enum IslandHeaderRecording {
    public enum Action: Equatable, Sendable {
        case stop
        case openMitamaMenu
        case startOnIsland
    }

    public static func action(ambientListenEnabled: Bool, mitamaAppInstalled: Bool) -> Action {
        if ambientListenEnabled { return .stop }
        return mitamaAppInstalled ? .openMitamaMenu : .startOnIsland
    }
}