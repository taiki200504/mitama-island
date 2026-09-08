import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// `SystemHUDCoordinator`'s policy: which key presses get swallowed, how they
/// move the backend, and how they present the HUD gauge. Every backend here
/// is a fake — nothing in this suite touches Accessibility, CoreAudio
/// hardware, or a private framework, so it runs the same on CI as on a
/// developer's Mac.
@MainActor
private final class FakeVolumeControl: VolumeControlling {
    var isAvailable = true
    var volume: Double = 0.5
    var muted = false

    func currentVolume() -> Double? { isAvailable ? volume : nil }
    func setVolume(_ volume: Double) { self.volume = volume }
    func isMuted() -> Bool? { isAvailable ? muted : nil }
    func setMuted(_ muted: Bool) { self.muted = muted }
}

@MainActor
private final class FakeBrightnessControl: BrightnessControlling {
    var isAvailable = true
    var level: Double = 0.5

    func currentBrightness() -> Double? { isAvailable ? level : nil }
    func setBrightness(_ level: Double) { self.level = level }
}

@MainActor
private final class FakeKeyboardBacklightControl: KeyboardBacklightControlling {
    /// Off by default, matching the real backend's own "unavailable unless
    /// the private symbols resolve" starting point.
    var isAvailable = false
    var level: Double = 0

    func currentLevel() -> Double? { isAvailable ? level : nil }
    func setLevel(_ level: Double) { self.level = level }
}

@MainActor
@Suite("SystemHUDCoordinator policy")
struct SystemHUDCoordinatorTests {
    private struct Fixture {
        let coordinator: SystemHUDCoordinator
        let settings: HUDSettings
        let volume: FakeVolumeControl
        let brightness: FakeBrightnessControl
        let keyboardBacklight: FakeKeyboardBacklightControl
        let overlay: OverlayUICoordinator
    }

    /// `replacesSystem` starts on and every per-meter switch at its normal
    /// default, so a test only has to override what it's actually about.
    private func makeFixture() -> Fixture {
        let name = "hud-coordinator-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        let settings = HUDSettings(store: PreferenceStore(suite: suite))
        settings.replacesSystem = true

        let volume = FakeVolumeControl()
        let brightness = FakeBrightnessControl()
        let keyboardBacklight = FakeKeyboardBacklightControl()
        let overlay = OverlayUICoordinator()

        let coordinator = SystemHUDCoordinator(
            tap: SystemKeyTap(),
            volume: volume,
            brightness: brightness,
            keyboardBacklight: keyboardBacklight,
            feedbackSound: {},
            modifierFlags: { [] }
        )
        coordinator.settings = settings
        coordinator.overlay = overlay

        return Fixture(
            coordinator: coordinator,
            settings: settings,
            volume: volume,
            brightness: brightness,
            keyboardBacklight: keyboardBacklight,
            overlay: overlay
        )
    }

    @Test("A key whose backend is unavailable is never swallowed and posts no gauge")
    func unavailableBackendIsNeverSwallowed() {
        let fixture = makeFixture()
        fixture.brightness.isAvailable = false

        #expect(fixture.coordinator.isEnabled(for: .brightnessUp) == false)
        fixture.coordinator.handle(key: .brightnessUp, isDown: true, isRepeat: false)
        #expect(fixture.overlay.sneakPeek == nil)
    }

    @Test("A volume key press adjusts the backend and posts a HUD gauge peek")
    func volumeKeyAdjustsAndPostsPeek() {
        let fixture = makeFixture()
        fixture.volume.volume = 0.5

        fixture.coordinator.handle(key: .volumeUp, isDown: true, isRepeat: false)

        #expect(abs(fixture.volume.volume - 0.5625) < 0.0001)
        #expect(fixture.overlay.sneakPeek?.kind == .hudGauge)
        #expect(fixture.overlay.sneakPeek?.text == "56%")
        #expect(fixture.overlay.sneakPeek?.gauge != nil)
    }

    @Test("A second press before the peek expires updates it in place rather than restarting its window")
    func secondPressUpdatesSamePeekInPlace() {
        let fixture = makeFixture()
        fixture.volume.volume = 0.5

        fixture.coordinator.handle(key: .volumeUp, isDown: true, isRepeat: false)
        let firstUntil = fixture.overlay.sneakPeek?.until

        fixture.coordinator.handle(key: .volumeUp, isDown: true, isRepeat: false)

        #expect(fixture.overlay.sneakPeek?.until == firstUntil)
        #expect(abs((fixture.overlay.sneakPeek?.gauge ?? 0) - 0.625) < 0.0001)
    }

    @Test("The master switch off disables every key regardless of per-meter settings")
    func masterSwitchOffDisablesEverything() {
        let fixture = makeFixture()
        fixture.settings.replacesSystem = false

        #expect(fixture.coordinator.isEnabled(for: .volumeUp) == false)
        fixture.coordinator.handle(key: .volumeUp, isDown: true, isRepeat: false)
        #expect(fixture.overlay.sneakPeek == nil)
    }

    @Test("A meter's own switch off disables just that meter, not the others")
    func perMeterSwitchDisablesJustThatMeter() {
        let fixture = makeFixture()
        fixture.settings.volume = false

        #expect(fixture.coordinator.isEnabled(for: .volumeUp) == false)
        #expect(fixture.coordinator.isEnabled(for: .brightnessUp) == true)
    }

    @Test("A key-up event does not adjust the backend or post a peek")
    func keyUpDoesNothing() {
        let fixture = makeFixture()
        fixture.volume.volume = 0.5

        fixture.coordinator.handle(key: .volumeUp, isDown: false, isRepeat: false)

        #expect(fixture.volume.volume == 0.5)
        #expect(fixture.overlay.sneakPeek == nil)
    }

    @Test("Mute toggles the backend and shows 0%")
    func muteTogglesAndShowsZero() {
        let fixture = makeFixture()
        fixture.volume.volume = 0.7
        fixture.volume.muted = false

        fixture.coordinator.handle(key: .mute, isDown: true, isRepeat: false)

        #expect(fixture.volume.muted == true)
        #expect(fixture.overlay.sneakPeek?.text == "0%")
    }

    @Test("The keyboard backlight, off by default, is never swallowed until its own switch is on")
    func keyboardBacklightOffByDefault() {
        let fixture = makeFixture()
        fixture.keyboardBacklight.isAvailable = true

        #expect(fixture.coordinator.isEnabled(for: .keyboardBacklightUp) == false)

        fixture.settings.keyboardBacklight = true
        #expect(fixture.coordinator.isEnabled(for: .keyboardBacklightUp) == true)
    }
}
