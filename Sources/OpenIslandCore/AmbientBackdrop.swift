import Foundation

/// The four slices of a day the ambient board's gradient tracks.
///
/// Fixed local hours rather than sunrise/sunset math: this is decoration
/// behind a clock, not a weather app, and a boundary that drifts twenty
/// minutes near a solstice is not worth a location permission or a network
/// call to avoid.
public enum TimeOfDayPhase: Equatable, Sendable {
    case dawn
    case day
    case dusk
    case night
}

public enum TimeOfDay: Sendable {
    /// No location, no calendar of sunrise times — just the hour on the
    /// clock the board is already drawing.
    public static func phase(for date: Date, calendar: Calendar = .current) -> TimeOfDayPhase {
        switch calendar.component(.hour, from: date) {
        case 5 ..< 8: .dawn
        case 8 ..< 17: .day
        case 17 ..< 20: .dusk
        default: .night
        }
    }
}

/// What the idle board draws behind the clock: the time-of-day gradient it
/// always has, or a video the owner dropped into the ambient folder.
public enum AmbientBackdrop: Equatable, Sendable {
    case gradient(TimeOfDayPhase)
    case video(URL)
}

/// The setting, independent of whether a video is actually available right
/// now — `AmbientBackdropPolicy` is what reconciles the two.
public enum AmbientBackdropPreference: String, Equatable, Sendable, CaseIterable {
    case gradient
    case video

    public var labelKey: String { "settings.display.ambientBackdrop.\(rawValue)" }
}

/// Whether the machine can afford to decode a looping video for as long as
/// the idle board stays up — the same trade-off `CameraPowerPolicy` makes
/// for the camera, reused rather than re-derived.
public enum AmbientBackdropPolicy: Sendable {
    public struct Conditions: Equatable, Sendable {
        public var onBattery: Bool
        public var lowPower: Bool
        public var thermalElevated: Bool

        public init(onBattery: Bool, lowPower: Bool, thermalElevated: Bool) {
            self.onBattery = onBattery
            self.lowPower = lowPower
            self.thermalElevated = thermalElevated
        }
    }

    /// Video only when it was actually asked for, a file exists to show, the
    /// machine can afford to decode it, and this is the one screen worth
    /// spending that decode on. Everything else falls back to the gradient
    /// for whatever moment `now` falls in — never to nothing.
    public static func resolve(
        preference: AmbientBackdropPreference,
        availableVideos: [URL],
        conditions: Conditions,
        isPrimaryDisplay: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> AmbientBackdrop {
        let phase = TimeOfDay.phase(for: now, calendar: calendar)
        guard preference == .video,
              isPrimaryDisplay,
              !conditions.onBattery, !conditions.lowPower, !conditions.thermalElevated,
              let url = AmbientVideoLibrary.pick(from: availableVideos, on: now, calendar: calendar)
        else {
            return .gradient(phase)
        }
        return .video(url)
    }
}

/// Filters and picks from whatever `.mov`/`.mp4`/`.m4v` files the app found
/// on disk. Takes the listing rather than reading the directory itself, so
/// which files exist stays a pure, testable question — the App target owns
/// the actual `FileManager` call.
public enum AmbientVideoLibrary: Sendable {
    private static let supportedExtensions: Set<String> = ["mov", "mp4", "m4v"]

    public static func videos(in directoryContents: [URL]) -> [URL] {
        directoryContents
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// The same clip all day, chosen by day-of-year so it doesn't reshuffle
    /// every time the machine happens to go idle.
    public static func pick(from videos: [URL], on date: Date, calendar: Calendar = .current) -> URL? {
        guard !videos.isEmpty else { return nil }
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 0
        return videos[dayOfYear % videos.count]
    }
}
