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
    /// Set by `AppModel`. The sequence is not a notification, but it should
    /// stay just as quiet — muted, or inside quiet hours — as anything else
    /// the app would have made noise about. Checked fresh before every cue in
    /// `playSoundtrack`, not only once at the start: the sequence runs for
    /// several seconds, long enough for a setting flipped partway through to
    /// matter.
    @ObservationIgnored var soundsAreSuppressed: () -> Bool = { false }
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

        heard = nil
        // Say the words only if that was asked for and the microphone is
        // available; otherwise the key that got here is enough on its own.
        // Permission that has not been granted counts as unavailable: waiting
        // nine seconds for a microphone that was never going to open is a dead
        // screen with no way to know why.
        let canListen = waitsForPhrase && voice != nil && VoiceCommandSession.canListenWithoutAsking
        stage = canListen ? .listening : .playing(startedAt: Date())

        presentPanels()

        if case .listening = stage {
            listenForPhrase()
        } else {
            scheduleDismissalAfterSequence()
            playSoundtrack()
        }
    }

    /// Presents the sequence already partway through, for the harness only:
    /// skips the phrase-listening step entirely and pins the picture — and
    /// fast-forwards any cue that would already have played — to
    /// `elapsedOverride` seconds in, so a screenshot doesn't have to wait out
    /// several real seconds of animation to find something worth capturing.
    func presentForHarness(elapsedOverride: TimeInterval) {
        dismiss()

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        Self.logger.notice("Presenting (harness) across \(screens.count) screen(s), pinned at \(elapsedOverride)s")

        heard = nil
        stage = .playing(startedAt: Date().addingTimeInterval(-elapsedOverride))
        presentPanels()

        scheduleDismissalAfterSequence()
        playSoundtrack(elapsedAtStart: elapsedOverride)
    }

    /// Builds and shows one panel per screen, and brings the app forward if
    /// it needs to be in order to receive the keystroke that dismisses them.
    /// Shared by `present()` and `presentForHarness(elapsedOverride:)`, which
    /// differ only in how `stage` gets set before this runs.
    private func presentPanels() {
        let screens = NSScreen.screens
        let mainScreen = NSScreen.main ?? screens[0]
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
    ///
    /// `elapsedAtStart` is 0 for a normal play — every cue is still ahead, so
    /// this behaves exactly as before. `presentForHarness` passes the pinned
    /// elapsed time instead: any cue at or before that point fires at once,
    /// so a screenshot taken moments later still finds the log it needs,
    /// rather than waiting out several real seconds it does not have.
    private func playSoundtrack(elapsedAtStart: TimeInterval = 0) {
        soundtrack?.cancel()
        guard !soundsAreSuppressed() else { return }

        soundtrack = Task { [weak self] in
            var previousAt: TimeInterval = elapsedAtStart
            for step in LinkstartSequence.cueSchedule {
                guard !Task.isCancelled, self != nil else { return }
                if step.at > previousAt {
                    try? await Task.sleep(for: .seconds(step.at - previousAt))
                }
                previousAt = max(previousAt, step.at)
                guard !Task.isCancelled, let self else { return }
                // Re-checked here rather than trusting the guard above: quiet
                // hours starting, or the speaker button being hit, partway
                // through the sequence should silence the very next cue —
                // muting once and then still hearing four more chimes reads
                // as the mute button not working.
                guard !self.soundsAreSuppressed() else { continue }
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
