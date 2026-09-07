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

    /// Whether the key stops at a dark screen and waits to be spoken into.
    ///
    /// Set by `AppModel` from the setting of the same name. Off means the key
    /// is the whole trigger, which is the default: the phrase adds three ways
    /// to fail to something that only plays an animation.
    @ObservationIgnored var waitsForPhrase = false

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
        // Say the words only if that was asked for and the microphone is
        // available; otherwise the key that got here is enough on its own.
        // Permission that has not been granted counts as unavailable: waiting
        // nine seconds for a microphone that was never going to open is a dead
        // screen with no way to know why.
        let canListen = waitsForPhrase && voice != nil && VoiceCommandSession.canListenWithoutAsking
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
    /// Timed from `LinkstartSequence.cueSchedule`, which is derived from the
    /// same durations the view draws from, so the sound and the picture cannot
    /// drift apart. These are cues synthesised for this app (see
    /// `docs/sound-design.md`), played directly by name rather than through
    /// `NotificationSoundEvent`: the sequence is not a notification and its
    /// three sounds are a fixed triad, not something anyone reassigns.
    private func playSoundtrack() {
        soundtrack?.cancel()
        guard !isMuted() else { return }

        soundtrack = Task { [weak self] in
            var previousAt: TimeInterval = 0
            for step in LinkstartSequence.cueSchedule {
                guard !Task.isCancelled, self != nil else { return }
                try? await Task.sleep(for: .seconds(step.at - previousAt))
                previousAt = step.at
                guard !Task.isCancelled, self != nil else { return }
                NotificationSoundService.play(Self.soundName(for: step.cue), volume: 0.5)
            }
        }
    }

    private static func soundName(for cue: LinkstartCue) -> String {
        switch cue {
        case .rise: "ui-linkstart-rise"
        case .tick: "ui-linkstart-tick"
        case .resolve: "ui-linkstart-resolve"
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
        FullScreenOverlayPanel.make(
            on: screen,
            rootView: LinkstartView(controller: self, showsDetail: showsDetail),
            onDismiss: { [weak self] in self?.dismiss() }
        )
    }
}
