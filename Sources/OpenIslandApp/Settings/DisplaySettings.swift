import Foundation
import Observation
import OpenIslandCore

/// Panel geometry, notch calibration, and which facts each session row carries.
final class DisplaySettings: PreferenceGroup {
    let registrar = ObservationRegistrar()
    let store: PreferenceStore

    init(store: PreferenceStore = .standard) {
        self.store = store
    }

    // MARK: System

    var contentFontSize: Double {
        get { read(\.contentFontSize, Keys.contentFontSize, Defaults.contentFontSize) }
        set { write(\.contentFontSize, Keys.contentFontSize, newValue) }
    }

    var maxPanelHeight: Double {
        get { read(\.maxPanelHeight, Keys.maxPanelHeight, Defaults.maxPanelHeight) }
        set { write(\.maxPanelHeight, Keys.maxPanelHeight, newValue) }
    }

    // MARK: Panel size

    var maxPanelWidth: Double {
        get { read(\.maxPanelWidth, Keys.maxPanelWidth, Defaults.maxPanelWidth) }
        set { write(\.maxPanelWidth, Keys.maxPanelWidth, newValue) }
    }

    /// The tallest a completion card may grow to. It still shrinks to fit a
    /// short message — this is a ceiling, not a fixed height, because pinning
    /// the height would either clip a long reply or pad a one-line one.
    var completionCardMaxHeight: Double {
        get { read(\.completionCardMaxHeight, Keys.completionCardMaxHeight, Defaults.completionCardMaxHeight) }
        set { write(\.completionCardMaxHeight, Keys.completionCardMaxHeight, newValue) }
    }

    /// Which set of agent marks the island draws. Stored as a raw string so an
    /// unknown future value falls back rather than failing to decode.
    var agentIconStyleRawValue: String {
        get { read(\.agentIconStyleRawValue, Keys.agentIconStyle, AgentIconStyle.pixel.rawValue) }
        set { write(\.agentIconStyleRawValue, Keys.agentIconStyle, newValue) }
    }

    /// Name each session after what it was first asked to do, instead of after
    /// the folder it runs in.
    var sessionAutoNaming: Bool {
        get { read(\.sessionAutoNaming, Keys.sessionAutoNaming, false) }
        set { write(\.sessionAutoNaming, Keys.sessionAutoNaming, newValue) }
    }

    /// Whether ⌃⌥L plays the login sequence.
    ///
    /// Off by default for the same reason every other global key here is: an
    /// unused shortcut still takes the combination away from whatever else the
    /// user bound it to.
    var playsLinkstart: Bool {
        get { read(\.playsLinkstart, Keys.playsLinkstart, false) }
        set { write(\.playsLinkstart, Keys.playsLinkstart, newValue) }
    }

    /// Whether the key only darkens the screen, and the sequence waits to be
    /// spoken into.
    ///
    /// Off by default. Speaking adds three ways to fail — microphone
    /// permission, what the recogniser writes down, and the room being quiet
    /// enough — to something that only plays an animation. Measured on
    /// 2026-08-29: one attempt in three got through, and the other two sat on a
    /// dark screen for nine seconds. The key that got here is proof enough.
    var linkstartWaitsForPhrase: Bool {
        get { read(\.linkstartWaitsForPhrase, Keys.linkstartWaitsForPhrase, false) }
        set { write(\.linkstartWaitsForPhrase, Keys.linkstartWaitsForPhrase, newValue) }
    }

    /// Put the next calendar entry on the closed island while nothing is
    /// waiting on you.
    ///
    /// Off by default because it needs calendar access, and a permission
    /// dialog that appears without the user having asked for anything is one
    /// nobody can answer confidently.
    var showsNextEvent: Bool {
        get { read(\.showsNextEvent, Keys.showsNextEvent, false) }
        set { write(\.showsNextEvent, Keys.showsNextEvent, newValue) }
    }

    /// Play a sound and put the entry on the closed island the instant it
    /// starts, for the first three minutes.
    ///
    /// Its own setting rather than folded into `showsNextEvent`, because
    /// wanting to be told the moment something starts is a different ask
    /// from wanting a quiet countdown to it — but it has nothing to watch
    /// without `showsNextEvent`'s calendar access already granted, which is
    /// why the row that controls this sits disabled until that one is on.
    var alertsWhenEventStarts: Bool {
        get { read(\.alertsWhenEventStarts, Keys.alertsWhenEventStarts, true) }
        set { write(\.alertsWhenEventStarts, Keys.alertsWhenEventStarts, newValue) }
    }

    /// How many minutes of the machine being left alone before the idle board
    /// takes the screen. Zero means never, which is the default.
    ///
    /// Off by default and staying that way: this is the one feature here that
    /// covers every display without being asked to. A screen that goes dark on
    /// its own during a call or a presentation is worse than no feature — the
    /// gates in `AppModel.considerAmbientBoard` exist for that reason.
    var ambientAfterMinutes: Int {
        get { read(\.ambientAfterMinutes, Keys.ambientAfterMinutes, 0) }
        set { write(\.ambientAfterMinutes, Keys.ambientAfterMinutes, newValue) }
    }

    /// Whether the idle board's backdrop is the time-of-day gradient or a
    /// video the owner dropped into the ambient folder. Raw string for the
    /// same reason `agentIconStyleRawValue` is.
    var ambientBackdropRawValue: String {
        get { read(\.ambientBackdropRawValue, Keys.ambientBackdrop, AmbientBackdropPreference.gradient.rawValue) }
        set { write(\.ambientBackdropRawValue, Keys.ambientBackdrop, newValue) }
    }

    /// Where to look for ambient videos. Empty means "the default
    /// Application Support folder", not "nothing configured" — there is
    /// nothing for the user to type here on first run.
    var ambientVideoFolderPath: String {
        get { read(\.ambientVideoFolderPath, Keys.ambientVideoFolderPath, "") }
        set { write(\.ambientVideoFolderPath, Keys.ambientVideoFolderPath, newValue) }
    }

    /// Announce a finished session in the middle of the screen.
    var completionBanner: Bool {
        get { read(\.completionBanner, Keys.completionBanner, true) }
        set { write(\.completionBanner, Keys.completionBanner, newValue) }
    }

    /// Keep rows that have gone grey out of the list entirely.
    var hideIdleSessions: Bool {
        get { read(\.hideIdleSessions, Keys.hideIdleSessions, true) }
        set { write(\.hideIdleSessions, Keys.hideIdleSessions, newValue) }
    }

    // MARK: Notch calibration

    /// Override for the notch height in points. Zero means "trust the macOS value".
    var notchHeightOverride: Double {
        get { read(\.notchHeightOverride, Keys.notchHeightOverride, 0) }
        set { write(\.notchHeightOverride, Keys.notchHeightOverride, newValue) }
    }

    /// Override for the notch width in points. Zero means "trust the macOS value".
    var notchWidthOverride: Double {
        get { read(\.notchWidthOverride, Keys.notchWidthOverride, 0) }
        set { write(\.notchWidthOverride, Keys.notchWidthOverride, newValue) }
    }

    // MARK: Session card contents

    var showTasks: Bool {
        get { read(\.showTasks, Keys.showTasks, true) }
        set { write(\.showTasks, Keys.showTasks, newValue) }
    }

    var showSubagents: Bool {
        get { read(\.showSubagents, Keys.showSubagents, true) }
        set { write(\.showSubagents, Keys.showSubagents, newValue) }
    }

    var showAgentActivity: Bool {
        get { read(\.showAgentActivity, Keys.showAgentActivity, true) }
        set { write(\.showAgentActivity, Keys.showAgentActivity, newValue) }
    }

    var showModel: Bool {
        get { read(\.showModel, Keys.showModel, false) }
        set { write(\.showModel, Keys.showModel, newValue) }
    }

    var showReasoningEffort: Bool {
        get { read(\.showReasoningEffort, Keys.showReasoningEffort, false) }
        set { write(\.showReasoningEffort, Keys.showReasoningEffort, newValue) }
    }

    var showWorktree: Bool {
        get { read(\.showWorktree, Keys.showWorktree, true) }
        set { write(\.showWorktree, Keys.showWorktree, newValue) }
    }

    var showProjectName: Bool {
        get { read(\.showProjectName, Keys.showProjectName, true) }
        set { write(\.showProjectName, Keys.showProjectName, newValue) }
    }

    // MARK: Shelf

    /// Raw string so an unknown future value falls back rather than failing to
    /// decode, the same reason `agentIconStyleRawValue` is stored this way.
    var shelfExpiresAfterRawValue: String {
        get { read(\.shelfExpiresAfterRawValue, Keys.shelfExpiresAfter, ShelfExpiryOption.never.rawValue) }
        set { write(\.shelfExpiresAfterRawValue, Keys.shelfExpiresAfter, newValue) }
    }
}

extension DisplaySettings {
    enum Defaults {
        /// The reference product offers this as a picker, not a slider, and
        /// labels 11pt as the default.
        static let contentFontSize: Double = 11
        static let contentFontSizeOptions: [Double] = [10, 11, 12, 13, 14, 15, 16]

        static let maxPanelHeight: Double = 560
        static let maxPanelHeightRange: ClosedRange<Double> = 280...900

        /// Matches the measured opened-surface width on a notched display.
        static let maxPanelWidth: Double = 648
        static let maxPanelWidthRange: ClosedRange<Double> = 480...900

        /// Floor matches the card's own chrome; anything less would clip the
        /// buttons. Ceiling is roughly half a laptop screen.
        static let completionCardMaxHeight: Double = 400
        static let completionCardMaxHeightRange: ClosedRange<Double> = 210...520

        static let notchOverrideRange: ClosedRange<Double> = 0...260
    }

    enum Keys {
        static let contentFontSize = "display.contentFontSize"
        static let maxPanelHeight = "display.maxPanelHeight"
        static let maxPanelWidth = "display.maxPanelWidth"
        // Renamed from `display.completionCardHeight`: that key stored a fixed
        // height the app never read, so reusing it would resurrect a 90pt value
        // that clips the card.
        static let completionCardMaxHeight = "display.completionCardMaxHeight"
        static let agentIconStyle = "display.agentIconStyle"
        /// No longer read — kept only so `migrateLegacyTheme` can clear a
        /// value an older build may have written.
        static let theme = "display.theme"
        static let completionBanner = "display.completionBanner"
        static let playsLinkstart = "display.playsLinkstart"
        static let linkstartWaitsForPhrase = "display.linkstartWaitsForPhrase"
        static let showsNextEvent = "display.showsNextEvent"
        static let alertsWhenEventStarts = "display.alertsWhenEventStarts"
        static let ambientAfterMinutes = "display.ambientAfterMinutes"
        static let ambientBackdrop = "display.ambientBackdrop"
        static let ambientVideoFolderPath = "display.ambientVideoFolderPath"
        static let hideIdleSessions = "display.hideIdleSessions"
        static let sessionAutoNaming = "display.sessionAutoNaming"
        static let notchHeightOverride = "display.notchHeightOverride"
        static let notchWidthOverride = "display.notchWidthOverride"
        static let showTasks = "display.sessionCard.showTasks"
        static let showSubagents = "display.sessionCard.showSubagents"
        static let showAgentActivity = "display.sessionCard.showAgentActivity"
        static let showModel = "display.sessionCard.showModel"
        static let showReasoningEffort = "display.sessionCard.showReasoningEffort"
        static let showWorktree = "display.sessionCard.showWorktree"
        static let showProjectName = "display.sessionCard.showProjectName"
        static let shelfExpiresAfter = "display.shelfExpiresAfter"
    }
}

extension DisplaySettings {
    /// One-time cleanup for the theme switcher this app used to have.
    ///
    /// The app now speaks only the SAO theme, so nothing reads `Keys.theme`
    /// any more — but a value written by an older build would otherwise sit
    /// in defaults forever. Called once from `SettingsStore.init`.
    static func migrateLegacyTheme(in store: PreferenceStore) {
        store.removeValue(forKey: Keys.theme)
    }
}
