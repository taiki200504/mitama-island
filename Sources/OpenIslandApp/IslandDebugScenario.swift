import AppKit
import CoreGraphics
import Foundation
import OpenIslandCore
import SwiftUI

struct IslandDebugSnapshot {
    let title: String
    let summary: String
    let previewHeight: CGFloat
    let notchStatus: NotchStatus
    let notchOpenReason: NotchOpenReason?
    let islandSurface: IslandSurface
    let sessions: [AgentSession]
    let selectedSessionID: String?
    /// The banner is a window of its own, so a scenario has to ask for it —
    /// loading sessions alone would never bring it up.
    var completionBanner: CompletionBannerContent?
    /// The idle board covers every screen, so a scenario has to ask for it the
    /// same way the banner does.
    var presentsAmbientBoard = false
    /// The login sequence is its own full-screen panel too, pinned partway
    /// through so the harness has something stable to capture rather than
    /// waiting out several real seconds of animation.
    var presentsLinkstart = false
    var linkstartElapsedOverride: TimeInterval = 0
    /// A sneak peek to present immediately after the overlay state loads.
    /// Only scenarios exercising the temporary closed-island message set
    /// this; `until` is set well past the kind's real duration so a headless
    /// capture always lands while it's still showing.
    var debugSneakPeek: IslandSneakPeek?
    /// Forces a timer accessory onto the closed island, independent of
    /// whether a real timer is running — how `closedAccessoryTimer` exercises
    /// the accessory in isolation.
    var debugAccessoryTimer: IslandClosedInputs.Timer?
    /// Items to put on the shelf before capture, and force the chip row open
    /// for — a scenario is the one caller with no pointer to hover with.
    var shelfItems: [ShelfItem] = []
    /// Poses `FocusTimerCoordinator` directly for the `timerSurface`
    /// scenario, with no run loop attached so a headless capture always
    /// lands on this exact remaining time.
    var debugTimerState: FocusTimerState?
    /// Loaded into `CalendarWatcher.loadFixture` rather than bypassing the
    /// arbiter directly — exercises the same `calendar.current` path the
    /// closed body, the opened island's join bar, and the ambient board all
    /// read from a real refresh.
    var debugCurrentEvent: UpcomingCalendarEvent.Current?
    /// Items to load straight into `ClipboardStore` for the
    /// `clipboardSurface` scenario — never through `record(_:)`, the same
    /// reasoning `shelfItems` gives for its own fixture loading.
    var debugClipboardItems: [ClipboardItem] = []
    /// Forces a now-playing accessory onto the closed island, independent of
    /// whether a real adapter process is running — how `nowPlayingClosed`
    /// exercises the accessory in isolation.
    var debugAccessoryNowPlaying: IslandClosedInputs.NowPlaying?
    /// Poses `NowPlayingCoordinator` directly for the `nowPlayingSurface`
    /// scenario, bypassing the perl adapter process entirely.
    var debugNowPlayingState: NowPlayingState?
}

enum IslandDebugScenario: String, CaseIterable, Identifiable {
    case closed
    case peekBand
    case sessionList
    case approvalCard
    case questionCard
    case completionCard
    case longCompletionCard
    case planApproval
    case completionBanner
    case longQuestionCard
    case ambientBoard
    case linkstart
    case sneakPeekPop
    case closedAccessoryTimer
    case shelfSurface
    case unlockScan
    case timerSurface
    case eventInProgress
    case clipboardSurface
    case nowPlayingClosed
    case nowPlayingSurface

    var id: String { rawValue }

    var title: String {
        switch self {
        case .closed:
            "Closed Notch"
        case .peekBand:
            "Peek Band"
        case .sessionList:
            "Session List"
        case .approvalCard:
            "Approval Card"
        case .questionCard:
            "Question Card"
        case .completionCard:
            "Completion Card"
        case .completionBanner:
            "The middle-of-screen announcement shown when a session finishes."
        case .longCompletionCard:
            "Long Completion Card"
        case .planApproval:
            "Plan Approval"
        case .completionBanner:
            "Completion Banner"
        case .longQuestionCard:
            "Long Question Card"
        case .ambientBoard:
            "Idle Board"
        case .linkstart:
            "Login Sequence"
        case .sneakPeekPop:
            "Sneak Peek Pop"
        case .closedAccessoryTimer:
            "Closed + Timer Accessory"
        case .shelfSurface:
            "Shelf Surface"
        case .unlockScan:
            "Unlock Greeting"
        case .timerSurface:
            "Timer Surface"
        case .eventInProgress:
            "Event In Progress"
        case .clipboardSurface:
            "Clipboard Surface"
        case .nowPlayingClosed:
            "Closed + Now Playing Accessory"
        case .nowPlayingSurface:
            "Now Playing Surface"
        }
    }

    var summary: String {
        switch self {
        case .closed:
            "Collapsed idle/running notch with live count and attention affordance."
        case .peekBand:
            "Collapsed notch while a request waits: who is waiting, and for how long."
        case .sessionList:
            "Manual expanded list with running, active, and inactive session rows."
        case .approvalCard:
            "Auto-expanded permission surface with approve and deny actions."
        case .planApproval:
            "Leaving plan mode, with the modes the agent offered as buttons."
        case .questionCard:
            "Auto-expanded question surface with selectable answer buttons."
        case .completionCard:
            "Auto-expanded finished-task reminder surface after a turn completes."
        case .longCompletionCard:
            "Long finished-task reply stays inside the card and scrolls internally."
        case .completionBanner:
            "The announcement shown under the notch when a session finishes."
        case .longQuestionCard:
            "Many long options: the list scrolls and the submit button stays put."
        case .ambientBoard:
            "The screen the machine shows while it is being left alone."
        case .linkstart:
            "The full-screen sequence that runs before the island lets you in, paused partway through."
        case .sneakPeekPop:
            "A temporary closed-island message overriding the body for a few seconds."
        case .closedAccessoryTimer:
            "Closed island with a waiting agent body and a running timer alongside it."
        case .shelfSurface:
            "Opened island with two items set aside, chips forced open for capture."
        case .unlockScan:
            "The ring-into-check greeting shown for a couple of seconds right after the screen unlocks."
        case .timerSurface:
            "The opened timer surface mid-Pomodoro, with its own controls and cycle dots."
        case .eventInProgress:
            "Closed island body while a calendar entry that just started is still fresh."
        case .clipboardSurface:
            "Opened island with three fixture clipboard items: text, a file, and an image."
        case .nowPlayingClosed:
            "Closed island with a waiting agent body and a now-playing accessory alongside it."
        case .nowPlayingSurface:
            "The opened now-playing surface with a fixture track, artwork placeholder, seek bar and transport controls."
        }
    }

    func snapshot(at now: Date = .now) -> IslandDebugSnapshot {
        switch self {
        case .closed:
            let sessions = DebugSessionFactory.listSessions(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 78,
                notchStatus: .closed,
                notchOpenReason: nil,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: sessions.first?.id
            )

        case .peekBand:
            // Eight minutes back, so the band has a real elapsed time to show
            // rather than the "just now" every freshly built fixture would give.
            let waiting = DebugSessionFactory.approvalSession(now: now.addingTimeInterval(-8 * 60))
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 78,
                notchStatus: .closed,
                notchOpenReason: nil,
                islandSurface: .sessionList(),
                sessions: DebugSessionFactory.notificationSessions(lead: waiting, now: now),
                selectedSessionID: waiting.id
            )

        case .sessionList:
            let sessions = DebugSessionFactory.listSessions(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 430,
                notchStatus: .opened,
                notchOpenReason: .click,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: sessions.first?.id
            )

        case .approvalCard:
            let session = DebugSessionFactory.approvalSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 330,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .planApproval:
            let session = DebugSessionFactory.planApprovalSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 380,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .questionCard:
            let session = DebugSessionFactory.questionSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 270,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .longQuestionCard:
            let session = DebugSessionFactory.longQuestionSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 420,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: [session],
                selectedSessionID: session.id
            )

        case .completionBanner:
            let session = DebugSessionFactory.completionSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 250,
                notchStatus: .closed,
                notchOpenReason: nil,
                islandSurface: .sessionList(),
                sessions: [session],
                selectedSessionID: session.id,
                completionBanner: CompletionBannerContent(
                    sessionID: session.id,
                    title: "mitama-island",
                    agentName: "Claude Code",
                    duration: "4分12秒"
                )
            )

        case .completionCard:
            let session = DebugSessionFactory.completionSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 250,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .longCompletionCard:
            let session = DebugSessionFactory.longCompletionSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 290,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .ambientBoard:
            // Two waiting agents eight and ninety minutes back, so the board
            // has both a "minutes" and an "hours" row to draw rather than the
            // "just now" every freshly built fixture would give.
            let recent = DebugSessionFactory.approvalSession(now: now.addingTimeInterval(-8 * 60))
            let stale = DebugSessionFactory.approvalSession(
                now: now.addingTimeInterval(-92 * 60),
                id: "session-approval-stale"
            )
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 78,
                notchStatus: .closed,
                notchOpenReason: nil,
                islandSurface: .sessionList(),
                sessions: [recent, stale],
                selectedSessionID: recent.id,
                presentsAmbientBoard: true
            )

        case .linkstart:
            let sessions = DebugSessionFactory.listSessions(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 78,
                notchStatus: .closed,
                notchOpenReason: nil,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: sessions.first?.id,
                presentsLinkstart: true,
                // Into the first sense's confirmation window: enough of the
                // opening burst and calibration flash have already passed
                // that there is something worth a screenshot.
                linkstartElapsedOverride: 3.5
            )

        case .sneakPeekPop:
            let sessions = DebugSessionFactory.listSessions(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 78,
                notchStatus: .closed,
                notchOpenReason: nil,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: sessions.first?.id,
                debugSneakPeek: IslandSneakPeek(
                    kind: .shelf,
                    text: "READY",
                    icon: "tray.full",
                    // Set well past the shelf kind's real 1.2s so a headless
                    // capture always lands while it's still showing — this
                    // fixture exists to be looked at, not to expire on cue.
                    until: now.addingTimeInterval(30)
                )
            )

        case .closedAccessoryTimer:
            let waiting = DebugSessionFactory.approvalSession(now: now.addingTimeInterval(-8 * 60))
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 78,
                notchStatus: .closed,
                notchOpenReason: nil,
                islandSurface: .sessionList(),
                sessions: DebugSessionFactory.notificationSessions(lead: waiting, now: now),
                selectedSessionID: waiting.id,
                debugAccessoryTimer: IslandClosedInputs.Timer(remainingMinutes: 12, label: "Focus")
            )

        case .nowPlayingClosed:
            let waiting = DebugSessionFactory.approvalSession(now: now.addingTimeInterval(-8 * 60))
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 78,
                notchStatus: .closed,
                notchOpenReason: nil,
                islandSurface: .sessionList(),
                sessions: DebugSessionFactory.notificationSessions(lead: waiting, now: now),
                selectedSessionID: waiting.id,
                debugAccessoryNowPlaying: IslandClosedInputs.NowPlaying(isPlaying: true)
            )

        case .shelfSurface:
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 220,
                notchStatus: .opened,
                notchOpenReason: .click,
                islandSurface: .sessionList(),
                sessions: [],
                selectedSessionID: nil,
                shelfItems: DebugSessionFactory.shelfFixtureItems(now: now)
            )

        case .unlockScan:
            let sessions = DebugSessionFactory.listSessions(now: now)
            // Pinned partway through the sequence — past the ring's own
            // 0.6s landing point — so a headless capture always finds the
            // ring full and the check already showing rather than racing
            // the animation.
            let pinnedElapsed: TimeInterval = 1.0
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 78,
                notchStatus: .closed,
                notchOpenReason: nil,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: sessions.first?.id,
                debugSneakPeek: IslandSneakPeek(
                    kind: .lockScan,
                    text: "Taiki",
                    icon: "person.crop.circle",
                    gauge: nil,
                    until: now.addingTimeInterval(LockScanSequence.duration - pinnedElapsed)
                )
            )

        case .timerSurface:
            let sessions = DebugSessionFactory.listSessions(now: now)
            // 12 minutes 34 seconds left in the third Pomodoro work session
            // (cycle 2 already finished) — an odd, specific remaining time so
            // a screenshot can't be confused with a fixture that just started.
            let remaining: TimeInterval = 12 * 60 + 34
            let timerState = FocusTimerState(
                mode: .pomodoro(),
                phase: .running(endsAt: now.addingTimeInterval(remaining)),
                cycle: 2,
                isRest: false,
                currentPhaseDuration: 25 * 60
            )
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 260,
                notchStatus: .opened,
                notchOpenReason: .click,
                islandSurface: .timer,
                sessions: sessions,
                selectedSessionID: sessions.first?.id,
                debugTimerState: timerState
            )

        case .eventInProgress:
            let sessions = DebugSessionFactory.listSessions(now: now)
            let startedAt = now.addingTimeInterval(-60)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 78,
                notchStatus: .closed,
                notchOpenReason: nil,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: sessions.first?.id,
                debugCurrentEvent: UpcomingCalendarEvent.Current(
                    title: "Design sync",
                    startsAt: startedAt,
                    endsAt: startedAt.addingTimeInterval(29 * 60),
                    url: URL(string: "https://zoom.us/j/5551234567")
                )
            )

        case .clipboardSurface:
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 320,
                notchStatus: .opened,
                notchOpenReason: .click,
                islandSurface: .clipboard,
                sessions: [],
                selectedSessionID: nil,
                debugClipboardItems: DebugSessionFactory.clipboardFixtureItems(now: now)
            )

        case .nowPlayingSurface:
            let sessions = DebugSessionFactory.listSessions(now: now)
            // 1:23 into a 4:56 track — odd, specific numbers so a screenshot
            // can't be confused with a fixture that just started or one
            // that's mid-playback by coincidence.
            let nowPlayingState = NowPlayingState(
                title: "Demo Track",
                artist: "Demo Artist",
                album: "Demo Album",
                isPlaying: true,
                elapsed: 83,
                duration: 296,
                timestamp: now,
                playbackRate: 1.0
            )
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 280,
                notchStatus: .opened,
                notchOpenReason: .click,
                islandSurface: .nowPlaying,
                sessions: sessions,
                selectedSessionID: sessions.first?.id,
                debugNowPlayingState: nowPlayingState
            )
        }
    }
}

private enum DebugSessionFactory {
    /// Two real files in a scratch directory, so the fixture's byte sizes are
    /// genuine rather than made up. `AppModel.loadDebugSnapshot` loads these
    /// straight into the shelf's memory rather than copying them in, so a
    /// harness run never touches the real Application Support shelf folder.
    static func shelfFixtureItems(now: Date) -> [ShelfItem] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenIslandShelfFixture-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let names = ["quarterly-report.pdf", "notes.md"]
        return names.enumerated().map { index, name in
            let url = directory.appendingPathComponent(name)
            let contents = Data(repeating: 0, count: 1024 * (index + 1))
            try? contents.write(to: url)
            let byteSize = Int64(
                (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? contents.count
            )
            return ShelfItem(
                displayName: name,
                storedName: name,
                byteSize: byteSize,
                addedAt: now.addingTimeInterval(-Double(index) * 60)
            )
        }
    }

    /// One text, one file, one image — the three kinds `ClipboardSurfaceView`
    /// has to draw a row for. Loaded straight into `ClipboardStore.items`
    /// (`loadFixture`, never `record`), so a harness run never touches the
    /// real pasteboard or the real Application Support clipboard folder.
    static func clipboardFixtureItems(now: Date) -> [ClipboardItem] {
        let swatch = NSImage(size: NSSize(width: 8, height: 8))
        swatch.lockFocus()
        NSColor(SAOGrammar.Palette.accentOrange).setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        swatch.unlockFocus()
        let pngData = swatch.tiffRepresentation
            .flatMap(NSBitmapImageRep.init(data:))?
            .representation(using: .png, properties: [:]) ?? Data()

        return [
            ClipboardItem(
                kind: .text("mitama-island clipboard fixture"),
                sourceBundleID: "com.apple.Terminal",
                copiedAt: now,
                contentHash: "fixture-text"
            ),
            ClipboardItem(
                kind: .fileURLs([URL(fileURLWithPath: "/tmp/quarterly-report.pdf")]),
                sourceBundleID: "com.apple.finder",
                copiedAt: now.addingTimeInterval(-60),
                contentHash: "fixture-file"
            ),
            ClipboardItem(
                kind: .image(pngData: pngData, thumbnail: pngData),
                sourceBundleID: nil,
                copiedAt: now.addingTimeInterval(-120),
                contentHash: "fixture-image"
            ),
        ]
    }

    static func listSessions(now: Date) -> [AgentSession] {
        [
            runningSession(now: now),
            recentCompletedSession(now: now),
            inactiveSession(
                id: "session-claude-research",
                workspace: "claude-research",
                initialPrompt: "我更关注获取的部分 我想在其他 app 里实时展示我的 usage。",
                latestPrompt: "为什么要查 Cursor 官方呢？这个事跟 Cursor 有什么关系？",
                assistant: "不建议按“最古老”来选。最古老不等于最轻量且最适合这个任务。",
                age: 27 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-personal",
                workspace: "Personal",
                initialPrompt: "[Image #1]我给你截了 3 张图，这个是我现在 Cursor 里面可用的模型。",
                latestPrompt: "[Image #1]我给你截了 3 张图，这个是我现在 Cursor 里面可用的模型。",
                assistant: "这张图里的模型，严格说不是这个 `voice-input` App 应该选的模…",
                age: 32 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-open-agent-sdk",
                workspace: "open-agent-sdk",
                initialPrompt: "OK，那现在你是不是需要提一个 PR？",
                latestPrompt: "那你直接提个 PR 吧",
                assistant: "PR 已经提好了：",
                age: 60 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-voice-input",
                workspace: "voice-input",
                initialPrompt: "看看 voice-input 这个仓库，重点关注模型选型。",
                latestPrompt: "严格来说它应该选哪个模型？",
                assistant: "如果目标是轻量实时，不建议直接按 Cursor 现成套餐来映射。",
                age: 78 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-agents",
                workspace: "agents",
                initialPrompt: "把你的分支和 worktree 都给我。",
                latestPrompt: "所以你是要先重启吗？",
                assistant: "已经重启了。现在跑的是新的 dev 进程。",
                age: 92 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-claude",
                workspace: "claude-code",
                initialPrompt: "我们先把整个 notch 的背景换成纯黑。",
                latestPrompt: "下面那块空白要去掉。",
                assistant: "展开态高度已经改成按内容自适应。",
                age: 118 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-hooks",
                workspace: "hooks",
                initialPrompt: "假如我想实时监控 Claude Code 的 usage 应该怎么做？",
                latestPrompt: "如果是在别的 app 里展示呢？",
                assistant: "代码里已经有几条更直接的路可以走。",
                age: 130 * 60,
                now: now
            ),
        ]
    }

    static func notificationSessions(lead: AgentSession, now: Date) -> [AgentSession] {
        var sessions = listSessions(now: now)
        if sessions.isEmpty {
            return [lead]
        }
        sessions[0] = lead
        return sessions
    }

    static func runningSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-running",
            title: "Codex · open-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .running,
            summary: "Reading IslandPanelView.swift and AppModel.swift",
            updatedAt: now.addingTimeInterval(-45),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/Personal/open-island",
                workingDirectory: "/Users/wangruobing/Personal/open-island",
                terminalSessionID: "ghostty-running"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "把 DEV 完全重构成一个 debug 页面，我需要稳定验收这些 card 的 UI。",
                lastUserPrompt: "之前也有错误的改动吧 你应该重新改",
                lastAssistantMessage: "读取现有 notch 状态与事件路由，准备把提醒态从 session list 里拆出来。",
                currentTool: "exec_command",
                currentCommandPreview: "sed -n '1,260p' Sources/OpenIslandApp/Views/SettingsView.swift"
            )
        )
    }

    static func recentCompletedSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-recent",
            title: "Codex · open-agent-sdk",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            summary: "The session list now matches the original island more closely.",
            updatedAt: now.addingTimeInterval(-3 * 60),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-agent-sdk",
                paneTitle: "codex ~/Personal/open-agent-sdk",
                workingDirectory: "/Users/wangruobing/Personal/open-agent-sdk",
                terminalSessionID: "ghostty-recent"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "读一下这篇论文 https://arxiv.org/html/2603.28052",
                lastUserPrompt: "读一下这篇论文 https://arxiv.org/html/2603.28052v1 感觉和我们在做的 agent 很像。",
                lastAssistantMessage: "整理完了，已经提炼出和 autoreserach 相关的几段关键差异。"
            )
        )
    }

    static func inactiveSession(
        id: String,
        workspace: String,
        initialPrompt: String,
        latestPrompt: String,
        assistant: String,
        age: TimeInterval,
        now: Date
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: "Codex · \(workspace)",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            summary: assistant,
            updatedAt: now.addingTimeInterval(-age),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: workspace,
                paneTitle: "codex ~/Personal/\(workspace)",
                workingDirectory: "/Users/wangruobing/Personal/\(workspace)",
                terminalSessionID: "ghostty-\(id)"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: initialPrompt,
                lastUserPrompt: latestPrompt,
                lastAssistantMessage: assistant
            )
        )
    }

    /// Leaving plan mode. The agent hands over the modes it will accept in
    /// `suggestedUpdates`; the card has to turn those into buttons.
    static func planApprovalSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-plan-approval",
            title: "Claude · open-island",
            tool: .claudeCode,
            origin: .demo,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Claude wants to exit plan mode and start implementation.",
            updatedAt: now.addingTimeInterval(-8),
            permissionRequest: PermissionRequest(
                title: "Exit plan mode",
                summary: "Claude wants to exit plan mode and start implementation.",
                affectedPath: "",
                primaryActionTitle: "Allow Once",
                secondaryActionTitle: "Deny",
                toolName: "ExitPlanMode",
                suggestedUpdates: [
                    .setMode(destination: .session, mode: .bypassPermissions),
                    .setMode(destination: .session, mode: .acceptEdits),
                ]
            ),
            jumpTarget: JumpTarget(
                terminalApp: "Cursor",
                workspaceName: "open-island",
                paneTitle: "claude ~/Personal/open-island",
                workingDirectory: "/Users/wangruobing/Personal/open-island",
                terminalSessionID: "cursor-plan"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                transcriptPath: "/tmp/plan.jsonl",
                initialUserPrompt: "残っている未修正を潰し切る計画を立てて",
                currentTool: "ExitPlanMode",
                currentToolInputPreview: "計画: 不要になったコードを削除し、提案をやめて実行に変える"
            )
        )
    }

    /// The id is a parameter so a scenario can show two waiting rows: two
    /// fixtures sharing one id make the session store trap on the duplicate.
    static func approvalSession(now: Date, id: String = "session-approval") -> AgentSession {
        AgentSession(
            id: id,
            title: "Codex · open-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Allow exec_command to rewrite SettingsView.swift?",
            updatedAt: now.addingTimeInterval(-20),
            permissionRequest: PermissionRequest(
                title: "Approve file rewrite",
                summary: "Allow exec_command to rewrite SettingsView.swift?",
                affectedPath: "Sources/OpenIslandApp/Views/SettingsView.swift",
                primaryActionTitle: "Allow",
                secondaryActionTitle: "Deny"
            ),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/Personal/open-island",
                workingDirectory: "/Users/wangruobing/Personal/open-island",
                terminalSessionID: "ghostty-approval"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "接下来我打算继续补齐一些能力。",
                lastUserPrompt: "askUserquestion 和权限审批，我想把他们也做到我们的 island 里。",
                lastAssistantMessage: "已经准备好重写 DEV 页面，需要批准文件改动。",
                currentTool: "exec_command",
                currentCommandPreview: "head -5000 /Users/wangruobing/Personal/claude-research/extracts/claude-bun-2.1.81-v3/islands/000_cli.js.txt"
            )
        )
    }

    static func questionSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-question",
            title: "Codex · open-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .waitingForAnswer,
            summary: "这个提醒态需要自动收起吗？",
            updatedAt: now.addingTimeInterval(-18),
            questionPrompt: QuestionPrompt(
                title: "Which authentication method should we use?",
                questions: [
                    QuestionPromptItem(
                        question: "Which authentication method should we use?",
                        header: "Auth",
                        options: [
                            QuestionOption(label: "JWT tokens", description: "Stateless, scalable"),
                            QuestionOption(label: "Session cookies", description: "Traditional approach"),
                            QuestionOption(label: "OAuth 2.0", description: "Third-party auth"),
                            QuestionOption(label: "Other", description: "", allowsFreeform: true),
                        ]
                    )
                ]
            ),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/Personal/open-island",
                workingDirectory: "/Users/wangruobing/Personal/open-island",
                terminalSessionID: "ghostty-question"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "原产品看起来像是单 notch surface + 多 content surface。",
                lastUserPrompt: "我们应该怎么做？",
                lastAssistantMessage: "建议先把 approvalCard、questionCard、completionCard 拆成独立 surface。"
            )
        )
    }

    /// Eight options, most of them long enough to wrap. The case the old card
    /// could not show: the list ran past the bottom and took the submit button
    /// with it.
    static func longQuestionSession(now: Date) -> AgentSession {
        var session = questionSession(now: now)
        session.id = "session-question-long"
        session.questionPrompt = QuestionPrompt(
            title: "How should the migration handle rows that fail validation?",
            questions: [
                QuestionPromptItem(
                    question: "How should the migration handle rows that fail validation?",
                    header: "Migration",
                    options: [
                        QuestionOption(
                            label: "Skip the row and write it to a rejects file for review afterwards",
                            description: "Nothing is lost, nothing blocks"
                        ),
                        QuestionOption(
                            label: "Stop the whole migration on the first failure so nothing half-applies",
                            description: "Safest, slowest to get through"
                        ),
                        QuestionOption(
                            label: "Coerce what can be coerced and skip only what cannot",
                            description: "Fewest rejects, hardest to audit"
                        ),
                        QuestionOption(
                            label: "Write every failure to the log and carry on regardless",
                            description: "Fast, easy to miss a problem"
                        ),
                        QuestionOption(
                            label: "Roll back to the last checkpoint and retry once",
                            description: "Handles a transient failure"
                        ),
                        QuestionOption(label: "Ask again per table", description: "Slow but precise"),
                        QuestionOption(label: "Use whatever the previous run did", description: ""),
                        QuestionOption(label: "Something else", description: "", allowsFreeform: true),
                    ]
                )
            ]
        )
        return session
    }

    static func completionSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-completion",
            title: "Codex · open-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            summary: "DEV 页面已经切到 mock-driven card 调试模式。",
            updatedAt: now.addingTimeInterval(-15),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/Personal/open-island",
                workingDirectory: "/Users/wangruobing/Personal/open-island",
                terminalSessionID: "ghostty-completion"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "这次我可能确实需要一些 mock 手段，让我能验收这些 Card 的 UI。",
                lastUserPrompt: "可以把 DEV 完全重构成一个 debug 页面。",
                lastAssistantMessage: "Plan 文件已写好。你的 hooks 触发情况如何？"
            )
        )
    }

    static func longCompletionSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-completion-long",
            title: "Codex · open-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            summary: "README 提交已经完成，长回复现在应该在卡片内部滚动。",
            updatedAt: now.addingTimeInterval(-45),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/Personal/open-island",
                workingDirectory: "/Users/wangruobing/Personal/open-island",
                terminalSessionID: "ghostty-completion-long"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "帮我把这个 README 也提交了，然后把结果贴给我。",
                lastUserPrompt: "顺便确认一下当前工作树和验证情况。",
                lastAssistantMessage: """
[README.md](/Users/wangruobing/Personal/open-island/README.md) 的现有改动已经单独提交了，commit 是 `f196316`，message 是 `docs: update readme tagline`。

这轮没有跑测试，因为只是文案改动。当前工作树是干净的，`main` 相对 `origin/main` 现在是 `ahead 6`。

如果你要我继续做下一轮，我建议把工作切到独立 worktree 里，这样不会和共享 `main` 上的并行改动互相打架。

下一步我会先检查当前仓库状态，然后从 `origin/main` 新建一个 worktree 和分支，在新工作区里继续处理这个样式问题并做完验证。
"""
            )
        )
    }
}
