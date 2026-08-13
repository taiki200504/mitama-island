import AppKit
import Carbon.HIToolbox
import Foundation
import OpenIslandCore

/// Decides which shortcuts exist right now, and what each one does.
///
/// Kept apart from the Carbon layer so the rules — which actions apply, which
/// scope they belong in, what a duplicate letter means — can be tested without
/// registering anything system-wide.
@MainActor
final class PanelHotkeyCoordinator {
    private let registrar: any HotkeyRegistering
    private let settings: ShortcutSettings
    private var resolver: KeycodeResolver
    private let layoutObserver = DistributedObserverBox()

    /// Called when a panel action fires. The receiver decides what it applies to.
    var onAction: ((PanelShortcutAction) -> Void)?
    /// The switcher key, with `true` when Shift was held to go backwards.
    var onSwitcherKey: ((Bool) -> Void)?
    var onSwitcherNavigate: ((Bool) -> Void)?
    var onSwitcherConfirm: (() -> Void)?
    var onSwitcherCancel: (() -> Void)?
    var onTouchlessActivation: (() -> Void)?
    var onVoiceAnswer: (() -> Void)?
    var onLinkstart: (() -> Void)?
    /// Off until the camera feature is switched on. A global shortcut that does
    /// nothing still takes ⌃⇧Space away from whatever else the user bound it to.
    /// Re-run `startPersistentBindings()` after changing this.
    var touchlessActivationEnabled = false
    /// Same rule as the camera: an unused global shortcut still takes the key
    /// away from whatever else the user bound it to.
    var voiceAnswerEnabled = false
    /// Same rule again: the sequence is a party trick, and a global key that
    /// nobody asked for should not hold ⌃⌥L hostage.
    var linkstartEnabled = false

    init(
        registrar: any HotkeyRegistering,
        settings: ShortcutSettings,
        resolver: KeycodeResolver = KeycodeResolver()
    ) {
        self.registrar = registrar
        self.settings = settings
        self.resolver = resolver

        registrar.onFire = { [weak self] id in
            self?.handleFire(id)
        }
        observeLayoutChanges()
    }

    private func handleFire(_ id: String) {
        switch id {
        case Self.switcherBindingID:        onSwitcherKey?(false)
        case Self.switcherReverseBindingID: onSwitcherKey?(true)
        case Self.switcherNextBindingID:    onSwitcherNavigate?(false)
        case Self.switcherPreviousBindingID: onSwitcherNavigate?(true)
        case Self.switcherConfirmBindingID: onSwitcherConfirm?()
        case Self.switcherCancelBindingID:  onSwitcherCancel?()
        case Self.touchlessActivationBindingID: onTouchlessActivation?()
        case Self.voiceAnswerBindingID: onVoiceAnswer?()
        case Self.linkstartBindingID: onLinkstart?()
        default:
            guard let action = PanelShortcutAction(rawValue: id) else { return }
            onAction?(action)
        }
    }

    // MARK: Switcher

    static let switcherBindingID = "switcher.open"
    static let switcherReverseBindingID = "switcher.openReverse"
    static let switcherNextBindingID = "switcher.next"
    static let switcherPreviousBindingID = "switcher.previous"
    static let switcherConfirmBindingID = "switcher.confirm"
    static let switcherCancelBindingID = "switcher.cancel"
    static let touchlessActivationBindingID = "touchlessActivation.begin"
    static let voiceAnswerBindingID = "voiceAnswer.begin"
    static let linkstartBindingID = "linkstart.play"

    /// Backtick, next to the shift key on every layout this app runs on. Not
    /// user-assignable: it is the one shortcut that has to be live all the time,
    /// so it has to be one that nothing else is likely to want.
    private static let backtickKeyCode: UInt16 = 50
    private static let returnKeyCode: UInt16 = 36
    private static let escapeKeyCode: UInt16 = 53
    private static let upArrowKeyCode: UInt16 = 126
    private static let downArrowKeyCode: UInt16 = 125

    /// True when macOS has reserved the camera trigger for itself. Carbon will
    /// still register it and still never deliver it, so this is the only way the
    /// UI can say why nothing happens.
    var touchlessActivationIsClaimedBySystem: Bool {
        SystemHotkeys.isClaimed(
            keyCode: TouchlessActivationTrigger.keyCode,
            modifiers: TouchlessActivationTrigger.modifiers,
            in: SystemHotkeys.current()
        )
    }

    /// The one always-live shortcut. Registered at startup and never released.
    func startPersistentBindings() {
        guard settings.keyboardShortcutsEnabled else { return }
        var bindings = [
            HotkeyBinding(
                id: Self.switcherBindingID,
                keyCode: Self.backtickKeyCode,
                modifiers: settings.modifier.flags,
                scope: .persistent
            )
        ]
        if touchlessActivationEnabled {
            bindings.append(
                HotkeyBinding(
                    id: Self.touchlessActivationBindingID,
                    keyCode: UInt16(TouchlessActivationTrigger.keyCode),
                    modifiers: NSEvent.ModifierFlags(rawValue: UInt(TouchlessActivationTrigger.modifiers)),
                    scope: .persistent
                )
            )
        }
        if voiceAnswerEnabled {
            bindings.append(
                HotkeyBinding(
                    id: Self.voiceAnswerBindingID,
                    keyCode: UInt16(VoiceAnswerTrigger.keyCode),
                    modifiers: NSEvent.ModifierFlags(rawValue: UInt(VoiceAnswerTrigger.modifiers)),
                    scope: .persistent
                )
            )
        }
        if linkstartEnabled {
            bindings.append(
                HotkeyBinding(
                    id: Self.linkstartBindingID,
                    keyCode: UInt16(LinkstartTrigger.keyCode),
                    modifiers: NSEvent.ModifierFlags(rawValue: UInt(LinkstartTrigger.modifiers)),
                    scope: .persistent
                )
            )
        }
        if settings.reverseSwitcherEnabled {
            bindings.append(
                HotkeyBinding(
                    id: Self.switcherReverseBindingID,
                    keyCode: Self.backtickKeyCode,
                    modifiers: [settings.modifier.flags, .shift],
                    scope: .persistent
                )
            )
        }
        registrar.setBindings(bindings, for: .persistent)
    }

    /// Arrow keys, return and escape, live only while the switcher is up.
    ///
    /// Escape and the arrows are far too common to hold permanently — this is
    /// the same discipline the single-letter panel keys follow.
    func switcherDidActivate() {
        registrar.setBindings(
            [
                HotkeyBinding(id: Self.switcherNextBindingID, keyCode: Self.downArrowKeyCode, modifiers: [], scope: .switcherActive),
                HotkeyBinding(id: Self.switcherPreviousBindingID, keyCode: Self.upArrowKeyCode, modifiers: [], scope: .switcherActive),
                HotkeyBinding(id: Self.switcherConfirmBindingID, keyCode: Self.returnKeyCode, modifiers: [], scope: .switcherActive),
                HotkeyBinding(id: Self.switcherCancelBindingID, keyCode: Self.escapeKeyCode, modifiers: [], scope: .switcherActive)
            ],
            for: .switcherActive
        )
    }

    func switcherDidDeactivate() {
        registrar.removeBindings(for: .switcherActive)
    }

    /// Registers the panel shortcuts. Called when the panel expands.
    func panelDidExpand() {
        guard settings.keyboardShortcutsEnabled else { return }
        registrar.setBindings(bindings(), for: .panelExpanded)
    }

    /// Releases them again, so a single letter is only ours while the panel is up.
    func panelDidCollapse() {
        registrar.removeBindings(for: .panelExpanded)
    }

    /// Re-registers with the current assignments, for when the user edits them
    /// while the panel happens to be open.
    func settingsDidChange(panelIsExpanded: Bool) {
        guard panelIsExpanded else { return }
        panelDidCollapse()
        panelDidExpand()
    }

    /// The bindings the current settings describe.
    ///
    /// Two actions assigned the same letter would race for the same Carbon
    /// registration, so the first one wins and the second is dropped — the
    /// settings pane flags the clash, and silently registering both would make
    /// which action fires depend on dictionary order.
    func bindings() -> [HotkeyBinding] {
        var used: Set<UInt16> = []
        var result: [HotkeyBinding] = []
        for action in PanelShortcutAction.allCases {
            guard let keyCode = resolver.keyCode(for: settings.key(for: action)),
                  !used.contains(keyCode) else { continue }
            used.insert(keyCode)
            result.append(
                HotkeyBinding(
                    id: action.rawValue,
                    keyCode: keyCode,
                    modifiers: settings.modifier.flags,
                    scope: .panelExpanded
                )
            )
        }
        return result
    }

    /// Actions whose letter could not be registered, so the pane can say which.
    func unresolvableActions() -> [PanelShortcutAction] {
        let registered = Set(bindings().map(\.id))
        return PanelShortcutAction.allCases.filter { !registered.contains($0.rawValue) }
    }

    // MARK: Layout changes

    /// Switching to a different keyboard moves the letters. Rebuilding the
    /// table is the only way ⌃Y keeps meaning "the Y key" afterwards.
    private func observeLayoutChanges() {
        layoutObserver.token = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.resolver = KeycodeResolver()
                self.settingsDidChange(panelIsExpanded: true)
            }
        }
    }
}


/// Holds a distributed-notification observer so `deinit` can remove it.
///
/// An observer that outlives its owner keeps a dead object's closure alive and
/// fires it on every keyboard change; `deinit` may not touch main-actor state.
private final class DistributedObserverBox: @unchecked Sendable {
    var token: NSObjectProtocol?

    deinit {
        if let token { DistributedNotificationCenter.default().removeObserver(token) }
    }
}
