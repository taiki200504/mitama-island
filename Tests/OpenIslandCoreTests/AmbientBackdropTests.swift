import Foundation
import Testing
@testable import OpenIslandCore

private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func utcDate(hour: Int, minute: Int = 0, day: Int = 15) -> Date {
    utcCalendar().date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour, minute: minute))!
}

@Suite struct TimeOfDayTests {
    private let calendar = utcCalendar()

    @Test func justBeforeDawnIsNight() {
        #expect(TimeOfDay.phase(for: utcDate(hour: 4, minute: 59), calendar: calendar) == .night)
    }

    @Test func dawnStartsAtFive() {
        #expect(TimeOfDay.phase(for: utcDate(hour: 5), calendar: calendar) == .dawn)
    }

    @Test func dayStartsAtEight() {
        #expect(TimeOfDay.phase(for: utcDate(hour: 7, minute: 59), calendar: calendar) == .dawn)
        #expect(TimeOfDay.phase(for: utcDate(hour: 8), calendar: calendar) == .day)
    }

    @Test func duskStartsAtSeventeen() {
        #expect(TimeOfDay.phase(for: utcDate(hour: 16, minute: 59), calendar: calendar) == .day)
        #expect(TimeOfDay.phase(for: utcDate(hour: 17), calendar: calendar) == .dusk)
    }

    @Test func nightStartsAtTwenty() {
        #expect(TimeOfDay.phase(for: utcDate(hour: 19, minute: 59), calendar: calendar) == .dusk)
        #expect(TimeOfDay.phase(for: utcDate(hour: 20), calendar: calendar) == .night)
    }

    @Test func midnightIsNight() {
        #expect(TimeOfDay.phase(for: utcDate(hour: 0), calendar: calendar) == .night)
    }
}

@Suite struct AmbientVideoLibraryTests {
    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/videos/\(name)") }

    @Test func filtersToSupportedExtensionsAndSortsByName() {
        let contents = [url("clip.mov"), url("notes.txt"), url("clip.mp4"), url("clip.m4v"), url("image.png")]
        let result = AmbientVideoLibrary.videos(in: contents)
        #expect(result.map(\.lastPathComponent) == ["clip.m4v", "clip.mov", "clip.mp4"])
    }

    @Test func extensionMatchIsCaseInsensitive() {
        #expect(AmbientVideoLibrary.videos(in: [url("clip.MOV")]).count == 1)
    }

    @Test func pickIsDeterministicForTheSameDay() {
        let videos = [url("a.mov"), url("b.mov"), url("c.mov")]
        let day = utcDate(hour: 9, day: 1)
        let calendar = utcCalendar()
        #expect(
            AmbientVideoLibrary.pick(from: videos, on: day, calendar: calendar)
                == AmbientVideoLibrary.pick(from: videos, on: day, calendar: calendar)
        )
    }

    @Test func pickCanDifferOnAnotherDay() {
        let videos = [url("a.mov"), url("b.mov"), url("c.mov")]
        let calendar = utcCalendar()
        let picks = Set((1 ... 3).map { day in
            AmbientVideoLibrary.pick(from: videos, on: utcDate(hour: 9, day: day), calendar: calendar)
        })
        #expect(picks.count > 1)
    }

    @Test func noFilesPicksNothing() {
        #expect(AmbientVideoLibrary.pick(from: [], on: .now) == nil)
    }
}

@Suite struct AmbientBackdropPolicyTests {
    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/videos/\(name)") }
    private let noon = utcDate(hour: 12)
    private let calendar = utcCalendar()
    private let clear = AmbientBackdropPolicy.Conditions(onBattery: false, lowPower: false, thermalElevated: false)

    @Test func gradientPreferenceIsAlwaysGradient() {
        let result = AmbientBackdropPolicy.resolve(
            preference: .gradient,
            availableVideos: [url("a.mov")],
            conditions: clear,
            isPrimaryDisplay: true,
            now: noon,
            calendar: calendar
        )
        #expect(result == .gradient(.day))
    }

    @Test func videoPreferenceWithAFileOnMainsPlaysVideo() {
        let videos = [url("a.mov")]
        let result = AmbientBackdropPolicy.resolve(
            preference: .video,
            availableVideos: videos,
            conditions: clear,
            isPrimaryDisplay: true,
            now: noon,
            calendar: calendar
        )
        #expect(result == .video(videos[0]))
    }

    @Test func noFilesFallsBackToGradientEvenWhenVideoIsAsked() {
        let result = AmbientBackdropPolicy.resolve(
            preference: .video,
            availableVideos: [],
            conditions: clear,
            isPrimaryDisplay: true,
            now: noon,
            calendar: calendar
        )
        #expect(result == .gradient(.day))
    }

    @Test func onBatteryFallsBackToGradient() {
        let conditions = AmbientBackdropPolicy.Conditions(onBattery: true, lowPower: false, thermalElevated: false)
        let result = AmbientBackdropPolicy.resolve(
            preference: .video, availableVideos: [url("a.mov")], conditions: conditions,
            isPrimaryDisplay: true, now: noon, calendar: calendar
        )
        #expect(result == .gradient(.day))
    }

    @Test func lowPowerFallsBackToGradient() {
        let conditions = AmbientBackdropPolicy.Conditions(onBattery: false, lowPower: true, thermalElevated: false)
        let result = AmbientBackdropPolicy.resolve(
            preference: .video, availableVideos: [url("a.mov")], conditions: conditions,
            isPrimaryDisplay: true, now: noon, calendar: calendar
        )
        #expect(result == .gradient(.day))
    }

    @Test func thermalElevatedFallsBackToGradient() {
        let conditions = AmbientBackdropPolicy.Conditions(onBattery: false, lowPower: false, thermalElevated: true)
        let result = AmbientBackdropPolicy.resolve(
            preference: .video, availableVideos: [url("a.mov")], conditions: conditions,
            isPrimaryDisplay: true, now: noon, calendar: calendar
        )
        #expect(result == .gradient(.day))
    }

    @Test func secondaryDisplayFallsBackToGradient() {
        let result = AmbientBackdropPolicy.resolve(
            preference: .video, availableVideos: [url("a.mov")], conditions: clear,
            isPrimaryDisplay: false, now: noon, calendar: calendar
        )
        #expect(result == .gradient(.day))
    }
}
