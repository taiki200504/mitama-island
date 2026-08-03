import SwiftUI

/// One entry in the settings sidebar.
///
/// The ordering and grouping mirror the reference product's own settings window
/// so the two can be compared pane by pane, with the Mitama-only panes
/// (appearance, watch, mitama) slotted in where they fit rather than appended.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case integrations
    case notifications
    case display
    case appearance
    case sound
    case usage

    case shortcuts
    case sshRemote
    case watch
    case labs

    case mitama
    case about

    var id: String { rawValue }

    var titleKey: String { "settings.tab.\(rawValue)" }

    func label(_ lang: LanguageManager) -> String { lang.t(titleKey) }

    var icon: String {
        switch self {
        case .general:       "gearshape.fill"
        case .integrations:  "puzzlepiece.extension.fill"
        case .notifications: "bell.fill"
        case .display:       "textformat.size"
        case .appearance:    "paintbrush.fill"
        case .sound:         "speaker.wave.2.fill"
        case .usage:         "gauge.with.needle.fill"
        case .shortcuts:     "keyboard.fill"
        case .sshRemote:     "globe"
        case .watch:         "applewatch"
        case .labs:          "flask.fill"
        case .mitama:        "antenna.radiowaves.left.and.right"
        case .about:         "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general:       .gray
        case .integrations:  .teal
        case .notifications: .red
        case .display:       .purple
        case .appearance:    .indigo
        case .sound:         .green
        case .usage:         .pink
        case .shortcuts:     Color(red: 0.85, green: 0.35, blue: 0.85)
        case .sshRemote:     .blue
        case .watch:         .cyan
        case .labs:          .orange
        case .mitama:        .mint
        case .about:         .blue
        }
    }

    var section: SettingsSection {
        switch self {
        case .general, .integrations, .notifications, .display, .appearance, .sound, .usage:
            .main
        case .shortcuts, .sshRemote, .watch, .labs:
            .advanced
        case .mitama, .about:
            .app
        }
    }
}

enum SettingsSection: String, CaseIterable {
    case main
    case advanced
    case app

    /// The first group carries no header in the reference product; repeating the
    /// app name above the last group is what it does instead.
    func header(_ lang: LanguageManager) -> String? {
        switch self {
        case .main:     nil
        case .advanced: lang.t("settings.section.advanced")
        case .app:      lang.t("app.name")
        }
    }

    var tabs: [SettingsTab] {
        SettingsTab.allCases.filter { $0.section == self }
    }
}
