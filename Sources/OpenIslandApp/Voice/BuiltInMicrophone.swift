import AVFAudio
import AudioToolbox
import CoreAudio
import os

enum BuiltInMicrophone {
    private static let logger = Logger(subsystem: "com.mitama.island", category: "audio")

    static func deviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        guard status == noErr else {
            logger.error("Cannot enumerate audio devices: \(status)")
            return nil
        }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard !devices.isEmpty else {
            logger.notice("No audio devices found; using the system input")
            return nil
        }
        status = devices.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, $0.baseAddress!)
        }
        guard status == noErr else {
            logger.error("Cannot read audio devices: \(status)")
            return nil
        }
        for device in devices {
            address.mSelector = kAudioDevicePropertyTransportType
            address.mScope = kAudioObjectPropertyScopeGlobal
            var transport: UInt32 = 0
            size = UInt32(MemoryLayout<UInt32>.size)
            status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport)
            guard status == noErr else {
                logger.error("Cannot read audio transport: \(status)")
                continue
            }
            guard transport == kAudioDeviceTransportTypeBuiltIn else { continue }
            address.mSelector = kAudioDevicePropertyStreams
            address.mScope = kAudioDevicePropertyScopeInput
            status = AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size)
            guard status == noErr else {
                logger.error("Cannot read input streams: \(status)")
                continue
            }
            if size >= MemoryLayout<AudioStreamID>.size { return device }
        }
        logger.notice("No built-in microphone found; using the system input")
        return nil
    }

    @discardableResult
    static func pin(_ engine: AVAudioEngine) -> Bool {
        guard var device = deviceID() else { return false }
        guard let audioUnit = engine.inputNode.audioUnit else {
            logger.error("Input audio unit unavailable; using the system input")
            return false
        }
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            logger.error("Cannot select the built-in microphone: \(status)")
            return false
        }
        return true
    }
}
