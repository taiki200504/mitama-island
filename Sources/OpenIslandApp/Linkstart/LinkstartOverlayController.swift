import AppKit
import Observation
import OpenIslandCore
import os
import SwiftUI

/// Puts the login sequence over every screen, and takes it away again.
///
/// Separate from `OverlayPanelController` on purpose: that one owns a small
/// panel that lives for the whole session and must never steal focus. This one
/// owns full-screen windows that exist for six seconds and are meant to be the
/// only thing you can see.
@MainActor
@Observable
final class LinkstartOverlayController {
    /// What the overlay is doing. The view draws from this.
    enum Stage: Equatable, Sendable {
        /// Waiting to be told to start. The screen is dark and says so.
        case listening
        /// Running, from this moment.
        case playing(startedAt: Date)
    }

    private static let logger = Logger(subsystem: "com.mitama.island", category: "linkstart")

    private(set) var stage: Stage = .listening
    /// What the microphone heard, shown back so a failed attempt is visible
    /// rather than silent.
    private(set) var heard: String?

    /// Set by `AppModel`. Nil when speaking is switched off, in which case the
    /// key alone plays the sequence.
    @ObservationIgnored var voice: VoiceCommandSession?

    @ObservationIgnored private var panels: [NSPanel] = []
    /// Whoever was in front before the sequence took over.
    @ObservationIgnored private var returnFocusTo: NSRunningApplication?
    @ObservationIgnored private var soundtrack: Task<Void, Never>?
    /// Set by `AppModel`. The sequence is not a notification, but the mute
    /// switch is about the machine making noise, and it means that here too.
    @ObservationIgnored var isMuted: () -> Bool = { false }
    @ObservationIgnored private var dismissal: Task<Void, Never>?

    var isPresenting: Bool { !panels.isEmpty }

    /// Shows the sequence. Called again while it is up, it takes it away —
    /// pressing the key twice is the same escape hatch the camera has.
    func toggle() {
        if isPresenting {
            dismiss()
            return
        }
        present()
    }

    func present() {
        dismiss()

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        Self.logger.notice("Presenting across \(screens.count) screen(s)")

        let mainScreen = NSScreen.main ?? screens[0]
        heard = nil
        // Say the words if the microphone is available; otherwise the key that
        // got here is enough on its own. Permission that has not been granted
        // counts as unavailable: waiting nine seconds for a microphone that was
        // never going to open is a dead screen with no way to know why.
        let canListen = voice != nil && VoiceCommandSession.canListenWithoutAsking
        stage = canListen ? .listening : .playing(startedAt: Date())

        panels = screens.map { screen in
            makePanel(
                on: screen,
                // The checklist belongs on the screen being looked at. Repeating
                // it on every display reads as a bug rather than as spectacle.
                showsDetail: screen == mainScreen
            )
        }

        // Key on one panel only: whichever has the key window is where Escape
        // and the closing click arrive.
        panels.first?.makeKeyAndOrderFront(nil)

        // A key window in a background app does not receive keystrokes, and
        // this covers every display — leaving the mouse as the only way out of
        // something that owns the whole screen is not acceptable. Come forward
        // for the length of the sequence and hand the front back on the way out.
        if !NSApp.isActive {
            returnFocusTo = NSWorkspace.shared.frontmostApplication
            NSApp.activate()
        }

        if case .listening = stage {
            listenForPhrase()
        } else {
            scheduleDismissalAfterSequence()
            playSoundtrack()
        }
    }

    // MARK: - Voice

    private func listenForPhrase() {
        guard let voice else { return }

        voice.onIntent = { [weak self] _, heard in
            guard let self, case .listening = self.stage else { return }
            self.heard = heard
            if LinkstartPhrase.isSpoken(in: heard) {
                Self.logger.notice("Phrase heard, starting")
                self.begin()
            } else {
                // Wrong words are not an error worth a dialog, but the screen
                // should not sit there as if nothing was said.
                Self.logger.notice("Heard something else; leaving")
                self.dismissShortly()
            }
        }
        voice.begin(options: [])

        // Nothing said at all: the microphone closes itself, and so should this.
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(9))
            guard !Task.isCancelled else { return }
            guard let self, case .listening = self.stage else { return }
            self.dismiss()
        }
    }

    /// Starts the sequence, whatever got us here.
    private func begin() {
        dismissal?.cancel()
        stage = .playing(startedAt: Date())
        scheduleDismissalAfterSequence()
        playSoundtrack()
    }

    /// Follows the choreography rather than the frames.
    ///
    /// Timed from the same durations the view draws from, so the sound and the
    /// picture cannot drift apart. The real thing's audio is someone else's
    /// work and cannot ship here — these are the nearest sounds already on the
    /// machine, which is the same compromise the SAO theme makes for
    /// notifications.
    private func playSoundtrack() {
        soundtrack?.cancel()
        guard !isMuted() else { return }

        soundtrack = Task { [weak self] in
            // The light arriving: low and sustained, not a notification chime.
            NotificationSoundService.play("Submarine", volume: 0.5)
            try? await Task.sleep(for: .seconds(LinkstartSequence.awakeningDuration))

            for _ in LinkstartSequence.senses {
                guard !Task.isCancelled, self != nil else { return }
                NotificationSoundService.play("Tink", volume: 0.35)
                try? await Task.sleep(for: .seconds(LinkstartSequence.perSenseDuration))
            }

            try? await Task.sleep(for: .seconds(LinkstartSequence.languageDuration))
            guard !Task.isCancelled, self != nil else { return }
            NotificationSoundService.play("Hero", volume: 0.5)
        }
    }

    private func scheduleDismissalAfterSequence() {
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(LinkstartSequence.duration + 1.0))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// Leaves the misheard text on screen just long enough to read.
    private func dismissShortly() {
        dismissal?.cancel()
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissal?.cancel()
        dismissal = nil
        soundtrack?.cancel()
        soundtrack = nil
        voice?.stop()
        guard !panels.isEmpty else { return }
        Self.logger.notice("Dismissing")
        panels.forEach { $0.orderOut(nil) }
        panels = []

        if let returnFocusTo, !returnFocusTo.isTerminated {
            returnFocusTo.activate()
        }
        returnFocusTo = nil
    }

    // MARK: - Private

    private func makePanel(on screen: NSScreen, showsDetail: Bool) -> NSPanel {
        let panel = LinkstartPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.onDismiss = { [weak self] in self?.dismiss() }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.ignoresMouseEvents = false
        // Above the menu bar and the Dock: this is meant to cover the machine.
        panel.level = .screenSaver
        // `.stationary` for the same reason the island needs it — without it the
        // panel is dragged off screen by the Sonoma wallpaper-reveal gesture.
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle, .stationary]

        let hosting = NSHostingView(
            rootView: LinkstartView(controller: self, showsDetail: showsDetail)
        )
        hosting.frame = CGRect(origin: .zero, size: screen.frame.size)
        panel.contentView = hosting
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        return panel
    }
}

/// A full-screen panel that anyone can get out of.
///
/// Something that covers every display has to be dismissable without knowing a
/// shortcut, so any key and any click take it away — not just Escape.
private final class LinkstartPanel: NSPanel {
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        onDismiss?()
    }

    override func mouseDown(with event: NSEvent) {
        onDismiss?()
    }
}
