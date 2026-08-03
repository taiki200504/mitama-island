import Foundation
import Observation

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

    var completionCardHeight: Double {
        get { read(\.completionCardHeight, Keys.completionCardHeight, Defaults.completionCardHeight) }
        set { write(\.completionCardHeight, Keys.completionCardHeight, newValue) }
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

        static let completionCardHeight: Double = 90
        static let completionCardHeightRange: ClosedRange<Double> = 90...260

        static let notchOverrideRange: ClosedRange<Double> = 0...260
    }

    enum Keys {
        static let contentFontSize = "display.contentFontSize"
        static let maxPanelHeight = "display.maxPanelHeight"
        static let maxPanelWidth = "display.maxPanelWidth"
        static let completionCardHeight = "display.completionCardHeight"
        static let notchHeightOverride = "display.notchHeightOverride"
        static let notchWidthOverride = "display.notchWidthOverride"
        static let showTasks = "display.sessionCard.showTasks"
        static let showSubagents = "display.sessionCard.showSubagents"
        static let showAgentActivity = "display.sessionCard.showAgentActivity"
        static let showModel = "display.sessionCard.showModel"
        static let showReasoningEffort = "display.sessionCard.showReasoningEffort"
        static let showWorktree = "display.sessionCard.showWorktree"
        static let showProjectName = "display.sessionCard.showProjectName"
    }
}
