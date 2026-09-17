import AppKit
import OpenIslandCore
import SwiftUI

/// Keeps the app reachable from the menu bar.
///
/// The island auto-hides and the Dock icon is off by default, so without this
/// there is nothing left to click once both are gone except reopening from a
/// terminal. One `NSStatusItem`, created and torn down by `show()`/`hide()`
/// as the user's preference changes; never touched by anything else.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private var statusItem: NSStatusItem?
    private var lastIconState: MenuBarIconRenderer.State?

    /// Closures for the menu currently on screen, indexed by `NSMenuItem.tag`.
    /// Rebuilt on every `menuNeedsUpdate`, so a stale entry is never one
    /// click away — the menu is always torn down and redrawn from
    /// `StatusMenuLayout` rather than diffed in place.
    private var actions: [() -> Void] = []

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.imagePosition = .imageOnly
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateIconImage()
    }

    func hide() {
        guard let item = statusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Update icon before building menu, in case state changed
        updateIconImage()

        menu.removeAllItems()
        actions.removeAll()

        let shelfItems = model.shelf.items
        var shelfIndex = 0

        for entry in StatusMenuLayout.entries(for: model.statusMenuInputs) {
            switch entry {
            case .openIsland(let waitingCount):
                addItem(
                    waitingCount > 0
                        ? model.lang.t("statusItem.openIsland.waiting", waitingCount)
                        : model.lang.t("statusItem.openIsland"),
                    to: menu
                ) { [weak model] in
                    model?.notchOpen(reason: .click)
                }
            case .toggleMute(let isMuted):
                addItem(
                    model.lang.t(isMuted ? "statusItem.unmute" : "settings.sound.mute"),
                    to: menu
                ) { [weak model] in
                    model?.toggleSoundMuted()
                }
            case .toggleCamera(let isWatching):
                addItem(
                    model.lang.t(isWatching ? "statusItem.cameraOff" : "statusItem.cameraOn"),
                    to: menu
                ) { [weak model] in
                    guard let model else { return }
                    if model.cameraActivation.isRunning {
                        model.cameraActivation.stop()
                    } else {
                        model.beginTouchlessActivation()
                    }
                }
            case .startTimer(let presets):
                let item = NSMenuItem(
                    title: model.lang.t("statusItem.timer.start"),
                    action: nil,
                    keyEquivalent: ""
                )
                let submenu = NSMenu()
                for preset in presets {
                    addItem(model.lang.t(preset.labelKey), to: submenu) { [weak model] in
                        model?.focusTimer.start(preset.mode)
                    }
                }
                item.submenu = submenu
                menu.addItem(item)
            case .timerRunning(let label):
                let item = NSMenuItem(
                    title: model.lang.t("statusItem.timer.running", label),
                    action: nil,
                    keyEquivalent: ""
                )
                item.isEnabled = false
                menu.addItem(item)
            case .stopTimer:
                addItem(model.lang.t("statusItem.timer.stop"), to: menu) { [weak model] in
                    model?.focusTimer.reset()
                }
            case .openClipboard:
                addItem(model.lang.t("statusItem.clipboard.open"), to: menu) { [weak model] in
                    model?.notchOpen(reason: .click, surface: .clipboard)
                }
            case .shelfHeader(let count):
                let header = NSMenuItem(
                    title: model.lang.t("statusItem.shelf.header", count),
                    action: nil,
                    keyEquivalent: ""
                )
                header.isEnabled = false
                menu.addItem(header)
            case .shelfItem(let name):
                guard shelfItems.indices.contains(shelfIndex) else { break }
                let shelvedItem = shelfItems[shelfIndex]
                shelfIndex += 1
                addItem(name, to: menu) { [weak model] in
                    guard let model else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([model.shelf.fileURL(for: shelvedItem)])
                }
            case .clearShelf:
                addItem(model.lang.t("shelf.clear"), to: menu) { [weak model] in
                    model?.shelf.removeAll()
                }
            case .separator:
                menu.addItem(.separator())
            case .settings:
                addItem(model.lang.t("statusItem.settings"), to: menu) { [weak model] in
                    model?.showSettings()
                }
            case .quit:
                addItem(model.lang.t("island.quit.confirmAction"), to: menu) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    // MARK: - Private

    /// Determines the current menu bar icon state from the app model and updates
    /// the status item's image if the state has changed.
    private func updateIconImage() {
        let newState = computeIconState()
        guard newState != lastIconState else { return }

        lastIconState = newState
        statusItem?.button?.image = MenuBarIconRenderer.image(for: newState)
    }

    /// Determines the icon state based on the current island state.
    /// Priority: approval needed > running > waiting > idle
    private func computeIconState() -> MenuBarIconRenderer.State {
        let inputs = model.statusMenuInputs

        // Check for approval/question needed first (highest priority)
        if inputs.hasPendingApprovals || inputs.hasPendingQuestions {
            return .approvalNeeded
        }

        // Check for running sessions
        if inputs.hasRunning {
            return .running
        }

        // Check for waiting sessions
        if inputs.hasWaiting {
            return .waiting
        }

        return .idle
    }

    private func addItem(_ title: String, to menu: NSMenu, action: @escaping () -> Void) {
        let item = NSMenuItem(title: title, action: #selector(runAction(_:)), keyEquivalent: "")
        item.target = self
        item.tag = actions.count
        actions.append(action)
        menu.addItem(item)
    }

    @objc
    private func runAction(_ sender: NSMenuItem) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag]()
    }

}
