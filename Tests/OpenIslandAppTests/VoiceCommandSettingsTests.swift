import Foundation
import OpenIslandCore
import Testing
@testable import OpenIslandApp

/// The microphone is the most invasive thing this app can open, so what keeps it
/// shut is worth pinning down.
@MainActor
struct VoiceCommandSettingsTests {
    private func makeSettings() -> VoiceCommandSettings {
        let name = "voice-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return VoiceCommandSettings(store: PreferenceStore(suite: suite))
    }

    @Test("Voice answering is off until it is switched on")
    func offByDefault() {
        #expect(makeSettings().isEnabled == false)
    }

    /// A mistaken press should not leave the microphone open for a minute, and a
    /// two-second window is too short to say "二番でお願いします".
    @Test("The listening window stays within a sane range")
    func windowIsClamped() {
        let settings = makeSettings()
        settings.windowSeconds = 900
        #expect(settings.windowSeconds == VoiceCommandSettings.Defaults.maximumWindowSeconds)
        settings.windowSeconds = 0
        #expect(settings.windowSeconds == VoiceCommandSettings.Defaults.minimumWindowSeconds)
    }

    @Test("Recognition defaults to Japanese, which decides the model to install")
    func defaultLocale() {
        #expect(makeSettings().locale.identifier == "ja-JP")
    }

    /// The trigger has to be one macOS does not reserve. ⌃⇧Space taught this the
    /// hard way: Carbon reported a successful registration and the key never came.
    @Test("The voice trigger avoids the combinations macOS reserves")
    func triggerAvoidsSystemShortcuts() {
        let entries = [
            SystemHotkeys.Entry(keyCode: 49, modifiers: 1048576, isEnabled: true),
            SystemHotkeys.Entry(keyCode: 49, modifiers: 262144 + 131072, isEnabled: true),
        ]
        #expect(
            SystemHotkeys.isClaimed(
                keyCode: VoiceAnswerTrigger.keyCode,
                modifiers: VoiceAnswerTrigger.modifiers,
                in: entries
            ) == false
        )
    }

    /// The camera and the microphone must not answer to the same keystroke.
    @Test("The camera and voice triggers are different keys")
    func triggersDoNotCollide() {
        #expect(
            (VoiceAnswerTrigger.keyCode, VoiceAnswerTrigger.modifiers)
                != (TouchlessActivationTrigger.keyCode, TouchlessActivationTrigger.modifiers)
        )
    }
}

/// Pressing the key with nothing on screen must not open the microphone.
@MainActor
struct VoiceAnswerTargetTests {
    private func makeModel() -> AppModel {
        let name = "voice-target-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return AppModel(settings: SettingsStore(store: PreferenceStore(suite: suite)))
    }

    private func waiting(_ id: String) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: "Claude · \(id)",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "waiting",
            updatedAt: Date(),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "demo",
                paneTitle: "claude",
                workingDirectory: "/tmp/\(id)",
                terminalSessionID: id
            )
        )
        session.permissionRequest = PermissionRequest(
            title: "Approve",
            summary: "Run a tool",
            affectedPath: "/tmp/\(id)",
            toolName: "Bash"
        )
        session.isProcessAlive = true
        return session
    }

    /// The feature exists to answer a question already asked. With nothing
    /// asked, there is no reason to listen — and the microphone stays shut.
    @Test("With nothing waiting the microphone is never opened")
    func nothingWaitingDoesNotListen() {
        let model = makeModel()
        model.settings.voiceCommand.isEnabled = true
        model.state = SessionState(sessions: [])

        model.beginVoiceAnswer()

        #expect(model.voiceAnswer.isRunning == false)
        // Said on the island, not only in a log: a shortcut that does nothing
        // and explains nothing is indistinguishable from a broken one.
        #expect(model.notice?.text == model.lang.t("voice.status.nothingToAnswer"))
    }

    /// Even with a card waiting, the switch decides. Off means the microphone
    /// is never touched and no permission is ever requested.
    @Test("A waiting card does not open the microphone while the feature is off")
    func disabledDoesNotListen() {
        let model = makeModel()
        model.state = SessionState(sessions: [waiting("a")])

        model.beginVoiceAnswer()

        #expect(model.voiceAnswer.isRunning == false)
    }
}
