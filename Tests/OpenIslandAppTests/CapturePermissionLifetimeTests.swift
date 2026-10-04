import AVFoundation
import Foundation
import Speech
import Testing
@testable import OpenIslandApp

@MainActor
struct CapturePermissionLifetimeTests {
    private final class CameraReplies {
        var callbacks: [@Sendable (Bool) -> Void] = []
        var starts = 0
    }
    private final class VoiceReplies {
        var microphone: [@Sendable (Bool) -> Void] = []
        var speech: [@Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void] = []
        var starts = 0
    }
    private func camera() -> (CameraActivationSession, CameraGestureSettings, CameraReplies) {
        let settings = CameraGestureSettings(store: PreferenceStore(suite: UserDefaults(suiteName: "camera-privacy-\(UUID().uuidString)")!))
        settings.isEnabled = true
        let replies = CameraReplies()
        return (CameraActivationSession(settings: settings, cameraAuthorization: { .notDetermined },
                                        requestCameraAccess: { replies.callbacks.append($0) },
                                        captureStart: { replies.starts += 1 }), settings, replies)
    }
    private func voice(microphoneAuthorized: Bool = false) -> (VoiceCommandSession, VoiceCommandSettings, VoiceReplies) {
        let settings = VoiceCommandSettings(store: PreferenceStore(suite: UserDefaults(suiteName: "voice-privacy-\(UUID().uuidString)")!))
        settings.isEnabled = true
        let replies = VoiceReplies()
        return (VoiceCommandSession(settings: settings,
                                    microphoneAuthorization: { microphoneAuthorized ? .authorized : .notDetermined },
                                    requestMicrophoneAccess: { replies.microphone.append($0) },
                                    speechAuthorization: { .notDetermined },
                                    requestSpeechAuthorization: { replies.speech.append($0) },
                                    recognitionStart: { replies.starts += 1 }), settings, replies)
    }
    private func settle() async throws { try await Task.sleep(for: .milliseconds(20)) }

    @Test func cameraGrantAfterStopCannotRestartCapture() async throws {
        let (session, _, replies) = camera()
        _ = session.begin()
        #expect(session.isRunning)
        session.stop()
        replies.callbacks[0](true)
        try await settle()
        #expect(replies.starts == 0)
        #expect(session.phase == .idle)
    }

    @Test func cameraDisabledBeforeGrantStaysIdle() async throws {
        let (session, settings, replies) = camera()
        _ = session.begin()
        settings.isEnabled = false
        replies.callbacks[0](true)
        try await settle()
        #expect(replies.starts == 0)
        #expect(session.phase == .idle)
    }

    @Test func cameraLatestRequestWinsOverAnOlderDenial() async throws {
        let (session, _, replies) = camera()
        _ = session.begin()
        session.stop()
        _ = session.begin()
        replies.callbacks[1](true)
        try await settle()
        replies.callbacks[0](false)
        try await settle()
        #expect(replies.starts == 1)
        #expect(session.phase == .awaitingGesture)
        session.stop()
    }

    @Test func cameraSecondPressCancelsAPendingPrompt() async throws {
        let (session, _, replies) = camera()
        _ = session.begin()
        _ = session.begin()
        #expect(replies.callbacks.count == 1)
        replies.callbacks[0](true)
        try await settle()
        #expect(replies.starts == 0)
        #expect(session.phase == .idle)
    }

    @Test func stoppedMicrophoneGrantDoesNotAskForSpeechOrStartListening() async throws {
        let (session, _, replies) = voice()
        session.begin(options: [])
        session.stop()
        replies.microphone[0](true)
        try await settle()
        #expect(replies.speech.isEmpty)
        #expect(replies.starts == 0)
        #expect(session.phase == .idle)
    }

    @Test func stoppedOrDisabledSpeechGrantCannotRestartListening() async throws {
        for disable in [false, true] {
            let (session, settings, replies) = voice(microphoneAuthorized: true)
            session.begin(options: [])
            if disable { settings.isEnabled = false } else { session.stop() }
            replies.speech[0](.authorized)
            try await settle()
            #expect(replies.starts == 0)
            #expect(session.phase == .idle)
        }
    }

    @Test func onlyTheLatestSpeechRequestCanStartListening() async throws {
        let (session, _, replies) = voice(microphoneAuthorized: true)
        session.begin(options: [])
        session.stop()
        session.begin(options: [])
        replies.speech[0](.denied)
        try await settle()
        #expect(session.isRunning)
        replies.speech[1](.authorized)
        try await settle()
        #expect(replies.starts == 1)
        #expect(session.phase == .listening)
        session.stop()
    }

    @Test func deniedPermissionNeverStartsDevices() async throws {
        let (cameraSession, _, cameraReplies) = camera()
        _ = cameraSession.begin()
        cameraReplies.callbacks[0](false)
        let (voiceSession, _, voiceReplies) = voice(microphoneAuthorized: true)
        voiceSession.begin(options: [])
        voiceReplies.speech[0](.denied)
        try await settle()
        #expect(cameraReplies.starts == 0)
        #expect(cameraSession.phase == .denied)
        #expect(voiceReplies.starts == 0)
        #expect(voiceSession.phase == .denied)
    }
    @Test func teardownWhilePermissionIsPendingCannotStartDevices() async throws {
        var cameraOwner: (CameraActivationSession, CameraGestureSettings, CameraReplies)? = camera()
        let cameraReplies = try #require(cameraOwner?.2)
        _ = cameraOwner?.0.begin()
        cameraOwner = nil
        cameraReplies.callbacks[0](true)
        var voiceOwner: (VoiceCommandSession, VoiceCommandSettings, VoiceReplies)? = voice(microphoneAuthorized: true)
        let voiceReplies = try #require(voiceOwner?.2)
        voiceOwner?.0.begin(options: [])
        voiceOwner = nil
        voiceReplies.speech[0](.authorized)
        try await settle()
        #expect(cameraReplies.starts == 0)
        #expect(voiceReplies.starts == 0)
    }

}
