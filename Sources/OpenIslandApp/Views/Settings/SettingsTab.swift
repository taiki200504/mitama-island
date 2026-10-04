import SwiftUI

/// One entry in the settings sidebar.
///
/// The ordering and grouping mirror the reference product's own settings window
/// so the two can be compared pane by pane, with the Mitama-only panes
/// (island, mitama) slotted in where they fit rather than appended. Appearance
/// lives inside display and the watch pairing inside integrations, so the
/// sidebar stays at twelve entries.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case integrations
    case notifications
    case display
    case island
    case sound
    case usage

    case shortcuts
    case sshRemote
    case labs

    case mitama
    case about

    var id: String { rawValue }

    var titleKey: String { "settings.tab.\(rawValue)" }

    func label(_ lang: LanguageManager) -> String { lang.t(titleKey) }

    static func matching(_ query: String, labels: [SettingsTab: String]) -> [SettingsTab] {
        let terms = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace).map(String.init)
        return allCases.filter { tab in
            let text = "\(labels[tab] ?? tab.rawValue) \(tab.rawValue) \(tab.searchKeywords)"
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return terms.allSatisfy { text.contains($0) }
        }
    }

    private var searchKeywords: String {
        switch self {
        case .general: "launch login language hover fullscreen sleep 起動 言語 ホバー 全画面 ログイン"
        case .integrations: "agent hooks setup pairing watch claude codex cursor paseo 連携 エージェント フック 接続"
        case .notifications: "alerts silence filters permissions approval auto response 通知 フィルター 許可 承認 自動応答"
        case .display: "appearance theme font width height screen notch 表示 外観 テーマ フォント サイズ 画面 ノッチ"
        case .island: "timer clipboard music now playing shelf hud タイマー クリップボード 音楽 再生 棚"
        case .sound: "audio volume mute quiet hours 音量 音声 サウンド ミュート 消音"
        case .usage: "quota rate limit reset claude codex 使用量 利用状況 上限 リセット"
        case .shortcuts: "keyboard hotkey gesture camera microphone voice ショートカット キーボード ジェスチャー カメラ マイク"
        case .sshRemote: "ssh remote terminal 遠隔 リモート ターミナル"
        case .labs: "experimental naming 実験 ラボ 名前"
        case .mitama: "feed automation jobs handoff scoreboard ミタマ 自動化 ジョブ 引継ぎ"
        case .about: "version update help バージョン 更新 アプリ情報"
        }
    }

    var icon: String {
        switch self {
        case .general:       "gearshape.fill"
        case .integrations:  "puzzlepiece.extension.fill"
        case .notifications: "bell.fill"
        case .display:       "textformat.size"
        case .island:        "capsule.fill"
        case .sound:         "speaker.wave.2.fill"
        case .usage:         "gauge.with.needle.fill"
        case .shortcuts:     "keyboard.fill"
        case .sshRemote:     "globe"
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
        case .island:        .indigo
        case .sound:         .green
        case .usage:         .pink
        case .shortcuts:     Color(red: 0.85, green: 0.35, blue: 0.85)
        case .sshRemote:     .blue
        case .labs:          .orange
        case .mitama:        .mint
        case .about:         .blue
        }
    }

    var section: SettingsSection {
        switch self {
        case .general, .integrations, .notifications, .display, .island, .sound, .usage:
            .main
        case .shortcuts, .sshRemote, .labs:
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
