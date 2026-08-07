import WatchKit

enum HapticManager {
    static func play(for message: WatchMessage) {
        switch message {
        case .permissionRequest:
            WKInterfaceDevice.current().play(.notification)
        case .question:
            WKInterfaceDevice.current().play(.directionUp)
        case .sessionCompleted:
            WKInterfaceDevice.current().play(.success)
        case .mitamaAlert:
            WKInterfaceDevice.current().play(.failure)
        case .resolved:
            break
        }
    }

    static func playConfirmation() {
        WKInterfaceDevice.current().play(.click)
    }
}
