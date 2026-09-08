import AppKit
import Foundation
import Observation
import OpenIslandCore

/// The volume backend `SystemHUDCoordinator` drives. A protocol so tests can
/// inject a fake instead of touching real CoreAudio hardware.
@MainActor
protocol VolumeControlling: AnyObject {
    var isAvailable: Bool { get }
    func currentVolume() -> Double?
    func setVolume(_ volume: Double)
    func isMuted() -> Bool?
    func setMuted(_ muted: Bool)
}

/// The brightness backend `SystemHUDCoordinator` drives — wraps a private
/// API, so `isAvailable` can legitimately be `false` on a real Mac.
@MainActor
protocol BrightnessControlling: AnyObject {
    var isAvailable: Bool { get }
    func currentBrightness() -> Double?
    func setBrightness(_ level: Double)
}

/// The keyboard backlight backend `SystemHUDCoordinator` drives — also a
/// private API, and off by default even when available.
@MainActor
protocol KeyboardBacklightControlling: AnyObject {
    var isAvailable: Bool { get }
    func currentLevel() -> Double?
    func setLevel(_ level: Double)
}

/// Turns volume/brightness/keyboard-backlight key presses into the island's
/// own HUD gauge instead of macOS's built-in on-screen display.
///
/// A key is only ever swallowed (see `SystemKeyTap`) when the master switch
/// is on, that meter's own switch is on, *and* the backend for it actually
/// works on this Mac — a key whose backend is unavailable always falls
/// through to macOS, which is the only way its own OSD can still show for it.
@MainActor
@Observable
final class SystemHUDCoordinator {
    private let tap: SystemKeyTap
    private let volume: any VolumeControlling
    private let brightness: any BrightnessControlling
    private let keyboardBacklight: any KeyboardBacklightControlling
    private let feedbackSound: () -> Void
    private let modifierFlags: () -> NSEvent.ModifierFlags

    @ObservationIgnored var settings: HUDSettings?
    /// Weak: the coordinator outlives no overlay, but nothing about a key
    /// press should keep the overlay coordinator alive past its own owner.
    @ObservationIgnored weak var overlay: OverlayUICoordinator?

    private(set) var isRunning = false

    init(
        tap: SystemKeyTap = SystemKeyTap(),
        volume: any VolumeControlling = AudioOutputControl(),
        brightness: any BrightnessControlling = DisplayBrightnessControl(),
        keyboardBacklight: any KeyboardBacklightControlling = KeyboardBacklightControl(),
        feedbackSound: @escaping () -> Void = SystemHUDCoordinator.playSystemFeedbackSound,
        modifierFlags: @escaping () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags }
    ) {
        self.tap = tap
        self.volume = volume
        self.brightness = brightness
        self.keyboardBacklight = keyboardBacklight
        self.feedbackSound = feedbackSound
        self.modifierFlags = modifierFlags
    }

    /// No-op without Accessibility — `isRunning` stays `false` and every key
    /// keeps reaching macOS untouched.
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        tap.onKey = { [weak self] key, isDown, isRepeat in
            self?.handle(key: key, isDown: isDown, isRepeat: isRepeat)
        }
        tap.shouldSwallow = { [weak self] key in
            self?.isEnabled(for: key) ?? false
        }
        isRunning = tap.start()
        return isRunning
    }

    func stop() {
        tap.stop()
        tap.onKey = nil
        tap.shouldSwallow = nil
        isRunning = false
    }

    private func gauge(for key: SystemKey) -> HUDGauge {
        switch key {
        case .volumeUp, .volumeDown, .mute: return .volume
        case .brightnessUp, .brightnessDown: return .brightness
        case .keyboardBacklightUp, .keyboardBacklightDown: return .keyboardBacklight
        }
    }

    private func backendIsAvailable(for gauge: HUDGauge) -> Bool {
        switch gauge {
        case .volume: return volume.isAvailable
        case .brightness: return brightness.isAvailable
        case .keyboardBacklight: return keyboardBacklight.isAvailable
        }
    }

    private func settingIsOn(for gauge: HUDGauge) -> Bool {
        guard let settings else { return false }
        return switch gauge {
        case .volume: settings.volume
        case .brightness: settings.brightness
        case .keyboardBacklight: settings.keyboardBacklight
        }
    }

    /// Whether `key` should be swallowed: the master switch is on, this
    /// meter's own switch is on, and a working backend exists for it.
    func isEnabled(for key: SystemKey) -> Bool {
        guard settings?.replacesSystem == true else { return false }
        let gauge = gauge(for: key)
        return settingIsOn(for: gauge) && backendIsAvailable(for: gauge)
    }

    /// Exposed (not `private`) so a policy test can drive key presses
    /// directly without a real `CGEvent` tap, `AXIsProcessTrusted`, or
    /// hardware behind the backends.
    func handle(key: SystemKey, isDown: Bool, isRepeat: Bool) {
        guard isDown, isEnabled(for: key) else { return }

        let fine = modifierFlags().contains([.option, .shift])
        let gauge = gauge(for: key)

        switch key {
        case .volumeUp, .volumeDown:
            let current = volume.currentVolume() ?? 0
            let next = HUDStepper.next(level: current, direction: key == .volumeUp ? 1 : -1, fine: fine)
            volume.setVolume(next)
            if next > 0, volume.isMuted() == true {
                volume.setMuted(false)
            }
            present(gauge: gauge, level: volume.isMuted() == true ? 0 : next)

        case .mute:
            let muted = !(volume.isMuted() ?? false)
            volume.setMuted(muted)
            present(gauge: gauge, level: muted ? 0 : (volume.currentVolume() ?? 0))

        case .brightnessUp, .brightnessDown:
            let current = brightness.currentBrightness() ?? 0
            let next = HUDStepper.next(level: current, direction: key == .brightnessUp ? 1 : -1, fine: fine)
            brightness.setBrightness(next)
            present(gauge: gauge, level: next)

        case .keyboardBacklightUp, .keyboardBacklightDown:
            let current = keyboardBacklight.currentLevel() ?? 0
            let next = HUDStepper.next(level: current, direction: key == .keyboardBacklightUp ? 1 : -1, fine: fine)
            keyboardBacklight.setLevel(next)
            present(gauge: gauge, level: next)
        }

        if settings?.playsFeedbackSound == true {
            feedbackSound()
        }
    }

    private func icon(for gauge: HUDGauge, level: Double) -> String {
        switch gauge {
        case .volume:
            if level <= 0 { return "speaker.slash.fill" }
            if level < 0.34 { return "speaker.wave.1.fill" }
            if level < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness:
            return level < 0.34 ? "sun.min.fill" : "sun.max.fill"
        case .keyboardBacklight:
            return "light.beacon.max.fill"
        }
    }

    /// Presents the gauge, or — if one from this coordinator is already
    /// showing — updates it in place rather than restarting its expiry, so a
    /// burst of presses reads as one gauge tracking the level rather than a
    /// new peek re-appearing on every press.
    private func present(gauge: HUDGauge, level: Double) {
        guard let overlay else { return }
        let text = "\(Int((level * 100).rounded()))%"
        let icon = icon(for: gauge, level: level)

        var updatedExisting = false
        overlay.updateSneakPeek(where: .hudGauge) { current in
            updatedExisting = true
            return IslandSneakPeek(kind: .hudGauge, text: text, icon: icon, gauge: level, until: current.until)
        }
        guard !updatedExisting else { return }

        overlay.presentSneakPeek(
            IslandSneakPeek(
                kind: .hudGauge,
                text: text,
                icon: icon,
                gauge: level,
                until: Date.now.addingTimeInterval(IslandSneakPeekPolicy.duration(for: .hudGauge))
            )
        )
    }

    /// `settings?.playsFeedbackSound` is the only gate the caller needs to
    /// have checked — this just plays, unconditionally, once asked. Whether
    /// that setting itself follows the live system preference is
    /// `HUDSettings.playsFeedbackSound`'s concern, not this one's: an
    /// explicit override of that setting has to actually take effect rather
    /// than being re-gated against the system value here.
    private static func playSystemFeedbackSound() {
        let path = "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"
        NSSound(contentsOfFile: path, byReference: true)?.play()
    }
}
