import AppKit
import Carbon.HIToolbox
import Foundation
import os

/// Registers shortcuts with Carbon's `RegisterEventHotKey`.
///
/// Carbon rather than an `NSEvent` global monitor on purpose: `RegisterEventHotKey`
/// needs **no Accessibility permission**, and it delivers the key without the
/// island having to take focus. The user keeps typing in their terminal and
/// still gets ⌃Y to approve.
@MainActor
final class CarbonHotkeyController: HotkeyRegistering {
    private static let logger = Logger(subsystem: "com.mitama.island", category: "hotkey")
    /// Four-character code identifying our hot keys to Carbon.
    private static let signature: OSType = 0x4D49534C // 'MISL'

    var onFire: ((String) -> Void)?

    private struct Registration {
        let ref: EventHotKeyRef
        let bindingID: String
    }

    private var registrations: [HotkeyScope: [Registration]] = [:]
    private var bindingIDsByCarbonID: [UInt32: String] = [:]
    private var nextCarbonID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    init() {
        installEventHandler()
    }

    deinit {
        // Carbon references are process-global; leaving them registered would
        // keep swallowing the key after the app stopped caring about it.
        MainActor.assumeIsolated {
            for scope in registrations.keys { removeBindings(for: scope) }
            if let eventHandler { RemoveEventHandler(eventHandler) }
        }
    }

    func setBindings(_ bindings: [HotkeyBinding], for scope: HotkeyScope) {
        // The panel scope is re-registered every time the island opens, so it
        // logs at debug. The always-live scope is registered once and is what
        // any "the key does nothing" investigation starts from — that one stays
        // at notice. Finding the ⌃⇧Space collision was impossible without it.
        if scope == .persistent {
            Self.logger.notice(
                "setBindings scope=persistent ids=\(bindings.map(\.id).joined(separator: ","), privacy: .public)"
            )
        } else {
            Self.logger.debug(
                "setBindings scope=\(String(describing: scope), privacy: .public) ids=\(bindings.map(\.id).joined(separator: ","), privacy: .public)"
            )
        }
        removeBindings(for: scope)

        var registered: [Registration] = []
        for binding in bindings {
            let carbonID = nextCarbonID
            nextCarbonID += 1

            var hotKeyID = EventHotKeyID(signature: Self.signature, id: carbonID)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(binding.keyCode),
                Self.carbonModifiers(from: binding.modifiers),
                hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &ref
            )
            _ = hotKeyID
            guard status == noErr, let ref else {
                // Another app already owns this combination. Skipping one
                // shortcut is right; failing the whole set is not.
                Self.logger.notice("Could not register \(binding.id, privacy: .public): \(status)")
                continue
            }
            bindingIDsByCarbonID[carbonID] = binding.id
            registered.append(Registration(ref: ref, bindingID: binding.id))
            if scope == .persistent {
                Self.logger.notice(
                    "Registered \(binding.id, privacy: .public) key=\(binding.keyCode) mods=\(binding.modifiers.rawValue)"
                )
            } else {
                Self.logger.debug(
                    "Registered \(binding.id, privacy: .public) key=\(binding.keyCode) mods=\(binding.modifiers.rawValue)"
                )
            }
        }
        registrations[scope] = registered
    }

    func removeBindings(for scope: HotkeyScope) {
        for registration in registrations[scope] ?? [] {
            UnregisterEventHotKey(registration.ref)
            bindingIDsByCarbonID = bindingIDsByCarbonID.filter { $0.value != registration.bindingID }
        }
        registrations[scope] = []
    }

    // MARK: Carbon plumbing

    private func installEventHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }

                let controller = Unmanaged<CarbonHotkeyController>.fromOpaque(context)
                    .takeUnretainedValue()
                let carbonID = hotKeyID.id
                // Carbon calls back on its own queue; everything the handler
                // touches is main-actor state.
                Task { @MainActor in controller.fire(carbonID: carbonID) }
                return noErr
            },
            1,
            &spec,
            context,
            &eventHandler
        )
    }

    private func fire(carbonID: UInt32) {
        guard let bindingID = bindingIDsByCarbonID[carbonID] else { return }
        onFire?(bindingID)
    }

    /// Carbon uses its own modifier constants, unrelated to `NSEvent`'s.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        return carbon
    }
}
