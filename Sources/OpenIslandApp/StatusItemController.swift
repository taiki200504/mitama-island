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

    /// Closures for the menu currently on screen, indexed by `NSMenuItem.tag`.
    /// Rebuilt on every `menuNeedsUpdate`, so a stale entry is never one
    /// click away — the menu is always torn down and redrawn from
    /// `StatusMenuLayout` rather than diffed in place.
    private var actions: [() -> Void] = []
    /// What the icon currently shows, so it is only redrawn when that changes.
    private var iconState: StatusIconState?

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
        iconState = nil
        trackIconState()
    }

    /// Redraws the icon whenever the sessions it summarises change, and only
    /// then — observation re-arms itself after each change rather than polling.
    private func trackIconState() {
        guard statusItem != nil else { return }
        let state = withObservationTracking {
            StatusIconState(attentionCount: model.liveAttentionCount, runningCount: model.liveRunningCount)
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackIconState() }
        }
        guard state != iconState else { return }
        iconState = state
        statusItem?.button?.image = StatusIconRenderer.image(for: state)
        statusItem?.button?.setAccessibilityValue(model.lang.t("statusItem.state.\(Self.stateKey(state))"))
    }

    private static func stateKey(_ state: StatusIconState) -> String {
        switch state {
        case .idle: "idle"
        case .running: "running"
        case .attention: "attention"
        }
    }

    func hide() {
        guard let item = statusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
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
            case .nowPlayingTrack(let title, let isPlaying):
                addItem(
                    model.lang.t(isPlaying ? "statusItem.nowPlaying.playing" : "statusItem.nowPlaying.paused", title),
                    to: menu
                ) { [weak model] in
                    model?.nowPlaying.togglePlayPause()
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

/// The menu bar icon: a crystal in the island's cut-corner grammar, reading at
/// a glance as idle (outline), working (a lit core) or waiting on you (solid).
/// A template image, so the menu bar tints it for light and dark.
enum StatusIconRenderer {
    static func image(for state: StatusIconState) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            draw(state, in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func draw(_ state: StatusIconState, in rect: NSRect) {
        NSColor.black.setStroke()
        NSColor.black.setFill()

        let outer = crystal(in: rect.insetBy(dx: 3, dy: 1.5))
        switch state {
        case .idle:
            outer.lineWidth = 1.4
            outer.stroke()
        case .running:
            outer.lineWidth = 1.4
            outer.stroke()
            crystal(in: rect.insetBy(dx: 6.5, dy: 5.5)).fill()
        case .attention:
            outer.fill()
            // A cut through the solid crystal, so "waiting" is not just a
            // heavier version of the same outline.
            NSGraphicsContext.current?.compositingOperation = .clear
            let bar = NSBezierPath(rect: NSRect(x: rect.midX - 0.9, y: rect.midY - 1, width: 1.8, height: 5.5))
            bar.fill()
            NSBezierPath(ovalIn: NSRect(x: rect.midX - 1, y: rect.midY - 4, width: 2, height: 2)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        }
    }

    /// An elongated diamond with its left and right points chamfered flat.
    private static func crystal(in rect: NSRect) -> NSBezierPath {
        let chamfer = rect.height * 0.14
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.midX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.midY + chamfer))
        path.line(to: NSPoint(x: rect.maxX, y: rect.midY - chamfer))
        path.line(to: NSPoint(x: rect.midX, y: rect.minY))
        path.line(to: NSPoint(x: rect.minX, y: rect.midY - chamfer))
        path.line(to: NSPoint(x: rect.minX, y: rect.midY + chamfer))
        path.close()
        return path
    }
}
