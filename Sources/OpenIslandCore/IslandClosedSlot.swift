import Foundation

/// What the closed island shows: one body slot, one trailing accessory.
///
/// The closed island used to decide these independently — a peek band, a
/// right-slot count, a center label — and nothing stopped two of them from
/// disagreeing about what mattered most, or from a waiting agent losing to
/// whichever one happened to render last. This collapses the decision into a
/// single priority order that never hides something waiting on you behind a
/// clock, and never lets an accessory push the thing that is actually waiting
/// off the island.
public enum IslandClosedBody: Equatable, Hashable, Sendable {
    /// A mitama alert nobody has acted on. Outranks everything: it lands in a
    /// database and says nothing on its own, unlike an agent, which already
    /// announced itself with a card.
    case urgent(IslandPeekBand.Content)
    /// The agent that has been waiting on you longest.
    case waiting(IslandPeekBand.Content)
    /// A calendar entry that just started. Shown only for the first three
    /// minutes — after that it stops being news and starts being a countdown
    /// nobody asked the island to keep.
    case eventStarted(title: String, startedAt: Date, url: URL?)
    /// What's next, while nothing above is asking for attention.
    case nextEvent(UpcomingCalendarEvent.Band)
}

/// The one trailing accessory the closed island has room for.
public enum IslandClosedAccessory: Equatable, Hashable, Sendable {
    /// Minutes only — a closed pill that re-ticks every second to show
    /// seconds would redraw a background app sixty times a minute.
    case timer(remainingMinutes: Int, label: String)
    case nowPlaying(isPlaying: Bool)
    /// macOS lights its own camera indicator for as long as the device runs;
    /// this is the island's only way to say why.
    case cameraWatching
    case shelf(count: Int)
}

/// Everything `IslandClosedArbiter` needs to decide, as plain values. Nothing
/// here is an EventKit, AVFoundation, or file-system type — those live in
/// `OpenIslandApp`, which is responsible for turning its own state into this.
public struct IslandClosedInputs: Sendable {
    /// A calendar entry that started, if one did — decoupled from whether it
    /// is still fresh enough to show; the arbiter applies the three-minute
    /// window.
    public struct EventStarted: Equatable, Hashable, Sendable {
        public let title: String
        public let startedAt: Date
        public let url: URL?

        public init(title: String, startedAt: Date, url: URL?) {
            self.title = title
            self.startedAt = startedAt
            self.url = url
        }
    }

    public struct Timer: Equatable, Hashable, Sendable {
        public let remainingMinutes: Int
        public let label: String

        public init(remainingMinutes: Int, label: String) {
            self.remainingMinutes = remainingMinutes
            self.label = label
        }
    }

    public var mitamaUrgent: IslandPeekBand.Content?
    public var waiting: IslandPeekBand.Content?
    public var eventStarted: EventStarted?
    public var nextEvent: UpcomingCalendarEvent.Band?
    public var showsNextEvent: Bool
    public var timer: Timer?
    public var nowPlayingIsPlaying: Bool?
    public var cameraIsWatching: Bool
    public var shelfCount: Int
    public var now: Date

    public init(
        mitamaUrgent: IslandPeekBand.Content? = nil,
        waiting: IslandPeekBand.Content? = nil,
        eventStarted: EventStarted? = nil,
        nextEvent: UpcomingCalendarEvent.Band? = nil,
        showsNextEvent: Bool = false,
        timer: Timer? = nil,
        nowPlayingIsPlaying: Bool? = nil,
        cameraIsWatching: Bool = false,
        shelfCount: Int = 0,
        now: Date = .now
    ) {
        self.mitamaUrgent = mitamaUrgent
        self.waiting = waiting
        self.eventStarted = eventStarted
        self.nextEvent = nextEvent
        self.showsNextEvent = showsNextEvent
        self.timer = timer
        self.nowPlayingIsPlaying = nowPlayingIsPlaying
        self.cameraIsWatching = cameraIsWatching
        self.shelfCount = shelfCount
        self.now = now
    }
}

public struct IslandClosedContent: Equatable, Hashable, Sendable {
    public var body: IslandClosedBody?
    public var accessory: IslandClosedAccessory?

    public init(body: IslandClosedBody? = nil, accessory: IslandClosedAccessory? = nil) {
        self.body = body
        self.accessory = accessory
    }
}

/// A calendar entry stops being "just started" after this long. Long enough
/// to catch the pill on the next 60-second tick; short enough that it never
/// turns into a countdown of how late the meeting already ran.
private let eventStartedFreshness: TimeInterval = 3 * 60

/// Decides the closed island's body and accessory as a pure function of
/// whatever is true right now. The view has nothing left to decide.
public enum IslandClosedArbiter {
    /// Body priority: a mitama alert beats a waiting agent beats a calendar
    /// entry that just started beats what's next. Accessory priority: a
    /// running timer beats now-playing beats "the camera is watching" beats
    /// the shelf having something on it.
    public static func resolve(_ inputs: IslandClosedInputs) -> IslandClosedContent {
        IslandClosedContent(body: resolveBody(inputs), accessory: resolveAccessory(inputs))
    }

    private static func resolveBody(_ inputs: IslandClosedInputs) -> IslandClosedBody? {
        if let urgent = inputs.mitamaUrgent {
            return .urgent(urgent)
        }
        if let waiting = inputs.waiting {
            return .waiting(waiting)
        }
        if let started = inputs.eventStarted {
            let elapsed = inputs.now.timeIntervalSince(started.startedAt)
            if elapsed >= 0, elapsed <= eventStartedFreshness {
                return .eventStarted(title: started.title, startedAt: started.startedAt, url: started.url)
            }
        }
        if inputs.showsNextEvent, let next = inputs.nextEvent {
            return .nextEvent(next)
        }
        return nil
    }

    private static func resolveAccessory(_ inputs: IslandClosedInputs) -> IslandClosedAccessory? {
        if let timer = inputs.timer {
            return .timer(remainingMinutes: timer.remainingMinutes, label: timer.label)
        }
        if let isPlaying = inputs.nowPlayingIsPlaying {
            return .nowPlaying(isPlaying: isPlaying)
        }
        if inputs.cameraIsWatching {
            return .cameraWatching
        }
        if inputs.shelfCount > 0 {
            return .shelf(count: inputs.shelfCount)
        }
        return nil
    }
}
