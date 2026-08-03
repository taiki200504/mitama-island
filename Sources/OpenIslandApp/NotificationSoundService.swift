import AppKit

/// Manages notification sound playback using macOS system sounds.
@MainActor
struct NotificationSoundService {
    private static let soundsDirectory = "/System/Library/Sounds"
    private static let defaultsKey = "notification.sound.name"
    static let defaultSoundName = "Bottle"

    /// Returns the list of available system sound names (without file extension).
    static func availableSounds() -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: soundsDirectory) else {
            return []
        }
        return contents
            .filter { $0.hasSuffix(".aiff") }
            .map { ($0 as NSString).deletingPathExtension }
            .sorted()
    }

    /// The currently selected sound name, persisted in UserDefaults.
    static var selectedSoundName: String {
        get {
            UserDefaults.standard.string(forKey: defaultsKey) ?? defaultSoundName
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
        }
    }

    /// Plays a system sound by name.
    static func play(_ name: String, volume: Double = 1) {
        guard let sound = NSSound(named: NSSound.Name(name)) else {
            return
        }
        sound.stop()
        sound.volume = Float(min(max(volume, 0), 1))
        sound.play()
    }

    /// Plays the sound assigned to an event, if anything should be heard.
    ///
    /// Mute, quiet hours and whether the event is one the app actually raises
    /// are all decided by `SoundSettings`; this only carries out the result.
    static func play(
        _ event: NotificationSoundEvent,
        settings: SoundSettings,
        at date: Date = Date()
    ) {
        guard settings.shouldPlay(event, at: date) else { return }
        play(settings.soundName(for: event), volume: settings.volume)
    }
}
