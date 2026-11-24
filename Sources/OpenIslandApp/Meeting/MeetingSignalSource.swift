import Foundation
import OpenIslandCore

/// Produces the `MeetingSignals` the detector reads. A protocol so the
/// coordinator can be driven by a fixture in tests and in the harness.
@MainActor
protocol MeetingSignalSource: AnyObject {
    func snapshot(at now: Date) -> MeetingSignals
}

#if os(macOS)
import AppKit
import CoreAudio
import CoreGraphics

/// Reads the live machine: who holds the microphone (CoreAudio), which apps
/// are running (NSWorkspace), browser window titles (CGWindowList — needs the
/// Screen Recording permission the recorder needs anyway), and the calendar
/// entry happening now (`CalendarWatcher`, through a closure).
@MainActor
final class SystemMeetingSignalSource: MeetingSignalSource {
    /// The calendar meeting happening now. Set once the calendar watcher is
    /// running; until then the calendar signal is simply absent.
    var calendarNow: (@MainActor () -> MeetingCalendarEntry?)?

    init() {}

    func snapshot(at now: Date) -> MeetingSignals {
        let mic = MicrophoneActivity.read()
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited }
            .map { MeetingSignals.RunningApp(bundleID: $0.bundleIdentifier, name: $0.localizedName ?? "") }
        // Titles are only worth reading while somebody is talking.
        let windows = mic.inUse ? Self.browserWindowTitles() : []
        return MeetingSignals(
            micInUse: mic.inUse,
            micClients: mic.clients,
            runningApps: apps,
            windowTitles: windows,
            calendarNow: calendarNow?(),
            at: now
        )
    }

    private static func browserWindowTitles() -> [MeetingSignals.WindowTitle] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        var bundleByPID: [pid_t: String?] = [:]
        var titles: [MeetingSignals.WindowTitle] = []
        for window in info {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let title = window[kCGWindowName as String] as? String,
                  !title.isEmpty
            else { continue }
            let bundleID: String?
            if let cached = bundleByPID[pid] {
                bundleID = cached
            } else {
                bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
                bundleByPID[pid] = bundleID
            }
            guard let bundleID, MeetingDetector.browserBundleIDs.contains(bundleID) else { continue }
            let owner = window[kCGWindowOwnerName as String] as? String ?? bundleID
            titles.append(MeetingSignals.WindowTitle(ownerBundleID: bundleID, ownerName: owner, title: title))
        }
        return titles
    }
}

/// Whether anyone other than this app is using a microphone.
///
/// macOS 14.4+ exposes per-process audio objects, which tell us *who* holds
/// the input and let us leave out the island's own engines (earshot, the
/// meeting recorder) — without that, recording would keep "the mic is in use"
/// true forever and a meeting would never end on mic idle.
///
/// Older systems fall back to `kAudioDevicePropertyDeviceIsRunningSomewhere`
/// on the default input, which cannot tell processes apart; there, a meeting
/// started by the island ends only when its app quits or the person stops it.
enum MicrophoneActivity {
    struct Reading: Sendable {
        var inUse: Bool
        var clients: [String]
    }

    static func read() -> Reading {
        if #available(macOS 14.4, *), let reading = readProcesses() {
            return reading
        }
        return Reading(inUse: defaultInputIsRunningSomewhere(), clients: [])
    }

    @available(macOS 14.4, *)
    private static func readProcesses() -> Reading? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return Reading(inUse: false, clients: []) }
        var objects = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return nil }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var clients: [String] = []
        for object in objects {
            guard uint32(object, kAudioProcessPropertyIsRunningInput) == 1 else { continue }
            let pid = pid_t(bitPattern: uint32(object, kAudioProcessPropertyPID) ?? 0)
            guard pid != ownPID else { continue }
            let bundleID = string(object, kAudioProcessPropertyBundleID)
                ?? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
                ?? "pid:\(pid)"
            clients.append(bundleID)
        }
        return Reading(inUse: !clients.isEmpty, clients: clients)
    }

    private static func defaultInputIsRunningSomewhere() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown
        else { return false }
        return uint32(device, kAudioDevicePropertyDeviceIsRunningSomewhere) == 1
    }

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        let text = value.takeRetainedValue() as String
        return text.isEmpty ? nil : text
    }
}
#endif
