import CoreAudio
import Foundation

/// Reads and writes the default output device's volume and mute state
/// through public CoreAudio — unlike brightness and the keyboard backlight,
/// audio needs no private framework.
@MainActor
final class AudioOutputControl: VolumeControlling {
    /// Always true: the CoreAudio calls this wraps are public API present on
    /// every Mac. A device with no volume control at all just makes
    /// `currentVolume()`/`setVolume(_:)` no-ops, which the coordinator
    /// already treats as "nothing to show" via the `nil` return.
    let isAvailable = true

    private func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    /// The element CoreAudio actually exposes volume on for `device` — the
    /// main element on most Macs, falling back to the left channel (1) for
    /// interfaces that only publish per-channel volume.
    private func volumeElement(for device: AudioDeviceID) -> AudioObjectPropertyElement? {
        for element in [kAudioObjectPropertyElementMain, 1] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: AudioObjectPropertyElement(element)
            )
            if AudioObjectHasProperty(device, &address) {
                return AudioObjectPropertyElement(element)
            }
        }
        return nil
    }

    func currentVolume() -> Double? {
        guard let device = defaultOutputDevice(), let element = volumeElement(for: device) else { return nil }
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else { return nil }
        return Double(volume)
    }

    func setVolume(_ volume: Double) {
        guard let device = defaultOutputDevice(), let element = volumeElement(for: device) else { return }
        var value = Float32(min(max(0, volume), 1))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
    }

    func isMuted() -> Bool? {
        guard let device = defaultOutputDevice() else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr else { return nil }
        return muted != 0
    }

    func setMuted(_ muted: Bool) {
        guard let device = defaultOutputDevice() else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return }
        var value = UInt32(muted ? 1 : 0)
        let size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
    }
}
