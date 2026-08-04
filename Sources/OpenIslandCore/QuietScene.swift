import Foundation

/// What macOS is doing right now, as far as we can honestly tell.
///
/// Each field is a tri-state rather than a `Bool`: "we looked and the answer is
/// no" and "we could not look" lead to different UI. Reporting an unreadable
/// signal as `false` would make a switch look effective when it never fires.
public enum QuietSignal: Equatable, Sendable {
    case active
    case inactive
    case unavailable

    public var isActive: Bool { self == .active }
    public var isReadable: Bool { self != .unavailable }
}

public struct QuietSceneSnapshot: Equatable, Sendable {
    /// `QuietFocusMode` raw values currently switched on, empty if none.
    /// `nil` when the Focus database could not be read at all.
    public var activeFocusModes: Set<String>?
    public var screenIsObscured: QuietSignal
    public var screenIsBeingShared: QuietSignal

    public init(
        activeFocusModes: Set<String>? = [],
        screenIsObscured: QuietSignal = .inactive,
        screenIsBeingShared: QuietSignal = .inactive
    ) {
        self.activeFocusModes = activeFocusModes
        self.screenIsObscured = screenIsObscured
        self.screenIsBeingShared = screenIsBeingShared
    }

    public static let unknown = QuietSceneSnapshot(
        activeFocusModes: nil,
        screenIsObscured: .unavailable,
        screenIsBeingShared: .unavailable
    )
}

/// Which of the detected scenes the user asked us to stay quiet during.
public struct QuietScenePolicy: Equatable, Sendable {
    public var quietFocusModes: Set<String>
    public var quietWhenScreenObscured: Bool
    public var quietWhenScreenCaptured: Bool

    public init(
        quietFocusModes: Set<String> = [],
        quietWhenScreenObscured: Bool = false,
        quietWhenScreenCaptured: Bool = false
    ) {
        self.quietFocusModes = quietFocusModes
        self.quietWhenScreenObscured = quietWhenScreenObscured
        self.quietWhenScreenCaptured = quietWhenScreenCaptured
    }

    /// A switch the user turned on can only fire on a signal we can actually
    /// read. An unavailable signal never silences anything — silently swallowing
    /// approvals because a lookup failed is far worse than one panel too many.
    public func shouldStayQuiet(in scene: QuietSceneSnapshot) -> Bool {
        if let active = scene.activeFocusModes, !active.isDisjoint(with: quietFocusModes) {
            return true
        }
        if quietWhenScreenObscured, scene.screenIsObscured.isActive { return true }
        if quietWhenScreenCaptured, scene.screenIsBeingShared.isActive { return true }
        return false
    }
}

// MARK: - Focus modes

/// Reads the Focus database macOS keeps in the user's home directory.
///
/// There is no public API for "which Focus is on", so this parses the same JSON
/// Notification Center writes. The shape has changed between macOS releases, so
/// rather than pinning one key path we walk the whole tree for any value under a
/// key ending in `ModeIdentifier`. That survives a reshuffle; a renamed
/// identifier prefix would not, and would show up as "no Focus is on".
public enum FocusModeReader {
    public static let defaultAssertionsPath = "Library/DoNotDisturb/DB/Assertions.json"

    /// Apple's identifiers for the Focus modes we expose a switch for.
    public static let identifiers: [String: String] = [
        "com.apple.donotdisturb.mode.default": "doNotDisturb",
        "com.apple.focus.personal-time": "personal",
        "com.apple.focus.work": "work",
        "com.apple.sleep.sleep-mode": "sleep"
    ]

    /// Returns the `QuietFocusMode` raw values that are on, or `nil` if the
    /// database was unreadable — a locked-down disk, a future macOS layout, or
    /// simply a Mac that has never had a Focus configured.
    public static func activeModes(inAssertionsAt url: URL) -> Set<String>? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        var found: Set<String> = []
        collectModeIdentifiers(in: root, into: &found)
        return Set(found.compactMap { identifiers[$0] })
    }

    private static func collectModeIdentifiers(in node: Any, into found: inout Set<String>) {
        switch node {
        case let dictionary as [String: Any]:
            for (key, value) in dictionary {
                // Case-insensitive: the key has appeared as both
                // `assertionDetailsModeIdentifier` and a bare `modeIdentifier`.
                if key.lowercased().hasSuffix("modeidentifier"), let identifier = value as? String {
                    found.insert(identifier)
                }
                collectModeIdentifiers(in: value, into: &found)
            }
        case let array as [Any]:
            for element in array { collectModeIdentifiers(in: element, into: &found) }
        default:
            break
        }
    }
}

// MARK: - Screen sharing

/// macOS exposes no API for "someone is recording or sharing my screen", so this
/// matches the bundle identifiers of the apps that do it.
///
/// The honest limits: sharing from a browser tab (Meet, a web Teams call) is
/// invisible here, and a listed app that is merely open but not sharing counts as
/// sharing. The help text says so rather than implying full coverage.
public enum ScreenSharingApps {
    public static let bundleIdentifiers: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.cisco.webexmeetingsapp",
        "com.obsproject.obs-studio",
        "com.apple.ScreenSharing",
        "com.apple.screencaptureui",
        "com.apple.QuickTimePlayerX",
        "com.loom.desktop",
        "com.tinyspeck.slackmacgap.helper.screensharing"
    ]

    public static func isSharing(runningBundleIdentifiers: Set<String>) -> Bool {
        !runningBundleIdentifiers.isDisjoint(with: bundleIdentifiers)
    }
}
