import Foundation
import Testing
@testable import OpenIslandApp

@MainActor
struct SoundSettingsTests {
    private func makeSettings() -> SettingsStore {
        let name = "sound-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return SettingsStore(store: PreferenceStore(suite: suite))
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 3
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    // MARK: Output

    @Test
    func soundsPlayAtFullVolumeUntilChanged() {
        let sound = makeSettings().sound
        #expect(!sound.isMuted)
        #expect(sound.volume == 1.0)
    }

    @Test
    func volumeIsClampedToARealRange() {
        let sound = makeSettings().sound

        sound.volume = 2.5
        #expect(sound.volume == 1)

        sound.volume = -3
        #expect(sound.volume == 0)
    }

    /// The island's speaker button and the sound pane write the same preference,
    /// so muting in one place has to show in the other.
    @Test
    func muteIsSharedWithTheIslandSpeakerButton() {
        let settings = makeSettings()
        let model = AppModel(settings: settings)

        model.isSoundMuted = true
        #expect(settings.sound.isMuted)

        settings.sound.isMuted = false
        #expect(!model.isSoundMuted)
    }

    // MARK: Playback decision

    @Test
    func mutingSilencesEveryEvent() {
        let sound = makeSettings().sound
        sound.isMuted = true

        for event in NotificationSoundEvent.allCases {
            #expect(!sound.shouldPlay(event, at: date(hour: 12)))
        }
    }

    @Test
    func onlyEventsTheAppRaisesCanPlay() {
        let sound = makeSettings().sound

        for event in NotificationSoundEvent.raisedEvents {
            #expect(sound.shouldPlay(event, at: date(hour: 12)), "\(event) should play")
        }
    }

    // MARK: Quiet hours

    @Test
    func quietHoursDoNothingUntilEnabled() {
        let sound = makeSettings().sound
        #expect(!sound.isWithinQuietHours(date(hour: 23)))
    }

    /// The default range runs 22:00 to 08:00, which is the case a naive
    /// start-to-end comparison gets wrong.
    @Test
    func anOvernightRangeCoversMidnight() {
        let sound = makeSettings().sound
        sound.quietHoursEnabled = true

        #expect(sound.isWithinQuietHours(date(hour: 23)))
        #expect(sound.isWithinQuietHours(date(hour: 3)))
        #expect(sound.isWithinQuietHours(date(hour: 22)))
        #expect(!sound.isWithinQuietHours(date(hour: 8)))
        #expect(!sound.isWithinQuietHours(date(hour: 13)))
    }

    @Test
    func aSameDayRangeStaysWithinTheDay() {
        let sound = makeSettings().sound
        sound.quietHoursEnabled = true
        sound.quietHoursStart = 9 * 60
        sound.quietHoursEnd = 17 * 60

        #expect(sound.isWithinQuietHours(date(hour: 12)))
        #expect(sound.isWithinQuietHours(date(hour: 9)))
        #expect(!sound.isWithinQuietHours(date(hour: 17)))
        #expect(!sound.isWithinQuietHours(date(hour: 3)))
    }

    /// An empty range would otherwise silence the whole day.
    @Test
    func anEmptyRangeSilencesNothing() {
        let sound = makeSettings().sound
        sound.quietHoursEnabled = true
        sound.quietHoursStart = 10 * 60
        sound.quietHoursEnd = 10 * 60

        #expect(!sound.isWithinQuietHours(date(hour: 10)))
        #expect(!sound.isWithinQuietHours(date(hour: 22)))
    }

    @Test
    func quietHoursSilenceAnEventThatWouldOtherwisePlay() {
        let sound = makeSettings().sound
        sound.quietHoursEnabled = true

        #expect(sound.shouldPlay(.approvalNeeded, at: date(hour: 13)))
        #expect(!sound.shouldPlay(.approvalNeeded, at: date(hour: 2)))
    }

    @Test
    func timesAreClampedToADay() {
        let sound = makeSettings().sound
        sound.quietHoursStart = 5_000
        #expect(sound.quietHoursStart == 24 * 60 - 1)

        sound.quietHoursEnd = -10
        #expect(sound.quietHoursEnd == 0)
    }

    // MARK: Assignments

    @Test
    func eachEventCanCarryItsOwnSound() {
        let sound = makeSettings().sound
        sound.setSoundName("Glass", for: .approvalNeeded)

        #expect(sound.soundName(for: .approvalNeeded) == "Glass")
        #expect(sound.soundName(for: .taskComplete) == SoundSettings.Defaults.soundName)
    }

    @Test
    func everyEventHasAVisibleLabel() {
        for event in NotificationSoundEvent.allCases {
            #expect(LanguageManager.shared.t(event.labelKey) != event.labelKey)
        }
    }

    @Test
    func clockLabelsArePaddedForAlignment() {
        #expect(SoundSettingsPane.clockLabel(0) == "00:00")
        #expect(SoundSettingsPane.clockLabel(9 * 60 + 30) == "09:30")
        #expect(SoundSettingsPane.clockLabel(22 * 60) == "22:00")
    }
}
