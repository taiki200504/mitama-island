import AppKit
import CoreGraphics
import OpenIslandCore

/// Installs a `CGEvent` tap on the system-defined event stream and decodes
/// the media-key events `SystemKeyEvent` understands. Returning `nil` from
/// the tap callback is the entire suppression mechanism — it is what stops
/// macOS from ever drawing its own volume/brightness OSD for a key this app
/// takes over.
///
/// Needs Accessibility (`AXIsProcessTrusted`); `start()` returns `false`
/// without it. The tap dies with the process, so a key silently returns to
/// macOS's own handling the moment the app quits or Accessibility is
/// revoked — there is no failure mode where a key simply stops responding.
@MainActor
final class SystemKeyTap {
    /// Fires for every decoded key, whether or not it ends up swallowed —
    /// the coordinator decides for itself whether `isDown` and its own
    /// settings mean it should act.
    var onKey: ((SystemKey, _ isDown: Bool, _ isRepeat: Bool) -> Void)?
    /// Asked only for a key-down; answers whether this app has a working,
    /// enabled backend for `key` right now. `false` lets the key fall
    /// through to macOS's own handling (and its own OSD) unchanged.
    var shouldSwallow: ((SystemKey) -> Bool)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    @discardableResult
    func start() -> Bool {
        stop()
        guard AXIsProcessTrusted() else { return false }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << 14), // NX_SYSDEFINED
            callback: systemKeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)?.takeRetainedValue() else {
            return false
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// macOS disables a tap that runs slowly or that the user has just
    /// interacted with a secure-input field under; without re-enabling it
    /// here the keys would silently stop being intercepted until relaunch.
    fileprivate func reenable() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    /// Returns `nil` to swallow the event (no macOS OSD, no macOS-side
    /// volume/brightness change), or the original event to let it through.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard
            let nsEvent = NSEvent(cgEvent: event),
            nsEvent.type == .systemDefined,
            let decoded = SystemKeyEvent.decode(subtype: Int(nsEvent.subtype.rawValue), data1: nsEvent.data1)
        else {
            return Unmanaged.passUnretained(event)
        }

        onKey?(decoded.key, decoded.isDown, decoded.isRepeat)

        guard decoded.isDown, shouldSwallow?(decoded.key) == true else {
            return Unmanaged.passUnretained(event)
        }
        return nil
    }
}

/// A free function rather than a closure literal, so it captures no context
/// and can be handed to `CGEvent.tapCreate` as a plain C function pointer —
/// the instance it calls back into travels through `userInfo` instead.
///
/// The tap is only ever installed on the main run loop (`start()` runs on
/// `@MainActor`, and `CFRunLoopGetCurrent()` at that point is the main run
/// loop), so this callback always fires on the main thread even though nothing
/// here is statically isolated.
private func systemKeyTapCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<SystemKeyTap>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { tap.reenable() }
        return Unmanaged.passUnretained(event)
    }

    return MainActor.assumeIsolated { tap.handle(type: type, event: event) }
}
