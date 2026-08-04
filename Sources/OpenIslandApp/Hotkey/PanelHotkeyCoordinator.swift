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

    init(
        registrar: any HotkeyRegistering,
        settings: ShortcutSettings,
        resolver: KeycodeResolver = KeycodeResolver()
    ) {
        self.registrar = registrar
        self.settings = settings
        self.resolver = resolver

        registrar.onFire = { [weak self] id in
            guard let action = PanelShortcutAction(rawValue: id) else { return }
            self?.onAction?(action)
        }
        observeLayoutChanges()
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
