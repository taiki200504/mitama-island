import AppKit
import OpenIslandCore

/// Manages notification sound playback using macOS system sounds.
@MainActor
struct NotificationSoundService {
    private static let soundsDirectory = "/System/Library/Sounds"
    private static let defaultsKey = "notification.sound.name"
    static let defaultSoundName = "Bottle"

    private static let customLibrary = CustomSoundLibrary(directory: CustomSoundLibrary.defaultDirectory())

    /// Bundled cue file stems offered for per-event assignment. `ui-hover`
    /// ships in the bundle but is never wired to anything (see `play(_:volume:)`
    /// below) and the three `ui-linkstart-*` files are a fixed rise/tick/resolve
    /// triad for the login sequence, not a sound anyone would pick for an
    /// ordinary event — both are left out of this list on purpose.
    private static let bundledCueNames = [
        "ui-open", "ui-close", "ui-select", "ui-confirm", "ui-approve", "ui-reject",
        "ui-warning", "ui-notify", "ui-urgent", "ui-complete", "ui-link",
        "ui-lock-scan", "ui-unlock", "ui-timer-end",
    ]

    /// Set once, at launch, when a harness scenario is driving the app.
    /// Diverts every cue into a log line instead of making noise: a
    /// screenshot run should not also play sound, and
    /// `validate-harness-artifacts.py` reads the line back to confirm the
    /// right cue fired.
    @MainActor static var harnessSink: ((String) -> Void)?

    /// Bundled cues first, then the system sounds and anything imported.
    static func availableSounds() -> [String] {
        bundledCueNames + (systemSounds() + customLibrary.soundNames())
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// A friendlier label for a stored sound name, for display in the picker.
    /// Bundled cues get "Crystal · <Cue>"; a system sound or an imported file
    /// is shown by its own name, since it already reads as one.
    static func displayLabel(for name: String) -> String {
        guard bundledCueNames.contains(name) else { return name }
        let cue = name
            .split(separator: "-")
            .dropFirst() // drop the shared "ui" prefix
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
        return "Crystal · \(cue)"
    }

    /// Returns the list of available system sound names (without file extension).
    static func systemSounds() -> [String] {
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

    /// Plays a sound by name: an imported file, a bundled cue, or a system
    /// sound, in that order.
    static func play(_ name: String, volume: Double = 1) {
        if let harnessSink {
            // Recorded, not played: the harness captures a still screen, and a
            // chime mid-capture would be noise nobody asked for.
            harnessSink("sound.cue=\(name)")
            return
        }

        let sound = resolvedSoundURL(named: name).flatMap { NSSound(contentsOf: $0, byReference: true) }
            ?? NSSound(named: NSSound.Name(name))
        guard let sound else { return }
        sound.stop()
        sound.volume = Float(min(max(volume, 0), 1))
        sound.play()
    }

    /// Where a name resolves to a playable file: an imported sound wins over a
    /// bundled cue of the same name, since the user chose it more recently and
    /// more deliberately. `nil` means the name only exists, if at all, as a
    /// macOS system sound — `NSSound(named:)` looks those up itself, by name
    /// rather than URL.
    ///
    /// Kept separate from `play` so the resolution order is testable without
    /// making noise, and so a custom library can be substituted in a test.
    static func resolvedSoundURL(named name: String, customLibrary: CustomSoundLibrary = customLibrary) -> URL? {
        customLibrary.url(forSoundNamed: name) ?? bundledSoundURL(named: name)
    }

    /// Looks up a cue shipped in `Resources/Sounds`. Checked under `Sounds/`
    /// first — where it lands in an Xcode-built bundle — then the bundle root,
    /// which is where SwiftPM's `.process` step flattens it to instead. Same
    /// two-step lookup as the bundled font in `IslandTypography`.
    static func bundledSoundURL(named name: String) -> URL? {
        Bundle.appResources.url(forResource: name, withExtension: "caf", subdirectory: "Sounds")
            ?? Bundle.appResources.url(forResource: name, withExtension: "caf")
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
