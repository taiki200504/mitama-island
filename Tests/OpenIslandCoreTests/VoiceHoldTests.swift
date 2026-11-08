import Foundation
import Testing
@testable import OpenIslandCore

/// Hold to talk for a spoken request (E2). The microphone never stays on by accident: a quick tap, the 60-second
/// ceiling and going to the background each stop it, and a stale result is dropped.
struct VoiceHoldTests {
    @Test
    func aPressMintsOneUUIDv4AndKeepsItThroughTheFinal() throws {
        var hold = VoiceHold()
        let pressed = hold.press()
        let id = try #require(pressed)
        #expect(VoiceHandoff.isUUIDv4(id))
        hold.partial("今日の")
        hold.release()
        let delivered = hold.final("今日の予定")
        let heard = try #require(delivered)
        #expect(heard.utteranceID == id)
        #expect(heard.text == "今日の予定")
        #expect(hold.phase == .idle)
    }

    @Test
    func aSecondPressWhileListeningDoesNothing() {
        var hold = VoiceHold()
        #expect(hold.press() != nil)
        #expect(hold.press() == nil)
    }

    @Test
    func tapAndReleaseBeforeTheMicStartsNeverStartsIt() throws {
        var hold = VoiceHold()
        let pressed = hold.press()
        let id = try #require(pressed)
        hold.release()
        let started = hold.startIfStillHeld(id)
        #expect(started == false)
        #expect(hold.phase == .idle)
    }

    @Test
    func aStartForAnOlderPressIsRefused() throws {
        var hold = VoiceHold()
        let first = hold.press()
        let old = try #require(first)
        hold.cancel()
        _ = hold.press()
        let started = hold.startIfStillHeld(old)
        #expect(started == false)
    }

    @Test
    func holdingToTheLimitReleasesByItself() {
        var hold = VoiceHold()
        _ = hold.press()
        #expect(VoiceHold.maxHold == 60)
        #expect(hold.shouldAutoRelease(heldFor: 59.9) == false)
        #expect(hold.shouldAutoRelease(heldFor: 60) == true)
        hold.release()
        #expect(hold.shouldAutoRelease(heldFor: 600) == false)
    }

    @Test
    func goingToTheBackgroundStopsAnActiveUtteranceAndDropsItsFinal() {
        var hold = VoiceHold()
        _ = hold.press()
        hold.partial("途中")
        let stopped = hold.appBackgrounded()
        #expect(stopped == true)
        let late = hold.final("遅れて届いた")
        #expect(late == nil)
        let again = hold.appBackgrounded()
        #expect(again == false)
    }

    @Test
    func silenceGivesNothingToSend() {
        var hold = VoiceHold()
        _ = hold.press()
        hold.release()
        #expect(hold.final("   ") == nil)
        #expect(hold.phase == .idle)
    }

    @Test
    func aFinalIsDeliveredOnce() {
        var hold = VoiceHold()
        _ = hold.press()
        hold.release()
        #expect(hold.final("a") != nil)
        #expect(hold.final("a") == nil)
    }
}

struct VoiceRequestSettingsTests {
    private func settings() -> VoiceRequestSettings { VoiceRequestSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!) }

    @Test
    func itIsOffUntilTheOwnerTurnsItOn() {
        let s = settings()
        #expect(s.isEnabled == false)
        s.isEnabled = true
        #expect(s.isEnabled == true)
        s.isEnabled = false
        #expect(s.isEnabled == false)
    }
}
