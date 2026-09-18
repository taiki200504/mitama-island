import OpenIslandCore
import SwiftUI

/// The opened `.conversation` surface: one session's log as message windows.
///
/// Reads the transcript only while this view is on screen, off the main
/// thread, and again whenever the session reports activity. Nothing is
/// watched in the background once the island closes.
struct ConversationSurfaceView: View {
    var model: AppModel
    let sessionID: String

    @State private var days: [ConversationDay] = []
    @State private var hasLoaded = false
    @State private var expanded: Set<String> = []

    private var lang: LanguageManager { model.lang }
    private var theme: SAOTheme { IslandThemes.current }
    private var session: AgentSession? { model.state.session(id: sessionID) }

    /// How many lines a long message shows before "show all".
    private static let collapsedLineLimit = 6
    private static let logHeight: CGFloat = 340

    var body: some View {
        VStack(spacing: 10) {
            header

            if model.conversationLogHidesText {
                notice(lang.t("conversation.hidden"), icon: "eye.slash")
            } else if hasLoaded && days.isEmpty {
                notice(lang.t("conversation.empty"), icon: "text.bubble")
            } else {
                log
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .task(id: session?.updatedAt) { await load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                model.notchOpen(reason: .click, surface: .sessionList())
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(V6Palette.paper.opacity(0.6))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lang.t("conversation.back"))

            Image(systemName: "diamond.fill")
                .font(.system(size: 8))
                .foregroundStyle(theme.accent)
                .shadow(color: theme.accent.opacity(0.8), radius: theme.glowRadius)

            Text(lang.t("conversation.title"))
                .saoCaps(size: 13, text: lang.t("conversation.title"))
                .foregroundStyle(V6Palette.paper.opacity(0.75))

            if let name = session?.spotlightWorkspaceName {
                Text(name)
                    .font(.islandMono(size: 10.5))
                    .foregroundStyle(V6Palette.paper.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) {
            // The gauge line under a window title.
            LinearGradient(colors: [theme.accent.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1.5)
                .offset(y: 6)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Log

    private var log: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(days) { day in
                        dayChip(day.day)
                        ForEach(day.runs) { run in
                            runView(run)
                        }
                    }
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .frame(height: Self.logHeight)
            .onChange(of: days) {
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
        }
    }

    private static let bottomID = "conversation-bottom"

    private func dayChip(_ day: Date?) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(V6Palette.paper.opacity(0.1)).frame(height: 1)
            Text(day.map { $0.formatted(.dateTime.year().month().day().weekday(.abbreviated)) } ?? "—")
                .font(.islandMono(size: 9.5, weight: .medium))
                .foregroundStyle(V6Palette.paper.opacity(0.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Self.chipShape.fill(V6Palette.paper.opacity(0.06)))
                .overlay(Self.chipShape.stroke(V6Palette.paper.opacity(0.14), lineWidth: 0.75))
            Rectangle().fill(V6Palette.paper.opacity(0.1)).frame(height: 1)
        }
        .padding(.vertical, 2)
    }

    private static let chipShape = SAOPanelShape(cornerRadius: 2, cuts: [.topLeading, .bottomTrailing], cutDepth: 4)

    /// A run of consecutive entries from one side: a speaker tag once, then
    /// its bubbles stacked close together.
    private func runView(_ run: ConversationRun) -> some View {
        VStack(alignment: run.isFromUser ? .trailing : .leading, spacing: 4) {
            speakerTag(isFromUser: run.isFromUser, time: run.entries.first?.timestamp)
            ForEach(run.entries) { entry in
                switch entry.kind {
                case let .tool(name, target):
                    toolLine(name: name, target: target)
                case .user, .assistant:
                    bubble(entry)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: run.isFromUser ? .trailing : .leading)
    }

    private func speakerTag(isFromUser: Bool, time: Date?) -> some View {
        HStack(spacing: 5) {
            Text(isFromUser ? lang.t("conversation.you") : (session?.tool.displayName ?? ""))
                .font(.islandMono(size: 9.5, weight: .bold))
                .foregroundStyle(isFromUser ? theme.accent : theme.statusTints.running)
            if let time {
                Text(time.formatted(date: .omitted, time: .shortened))
                    .font(.islandMono(size: 9))
                    .foregroundStyle(V6Palette.paper.opacity(0.35))
            }
        }
    }

    /// A message window. The corner nearest the speaker is cut, so the shape
    /// itself says which way the message came from.
    private func bubble(_ entry: ConversationEntry) -> some View {
        let isUser = entry.isFromUser
        let shape = SAOPanelShape(
            cornerRadius: 6,
            cuts: isUser ? [.topTrailing] : [.topLeading],
            cutDepth: 8
        )
        let tint = isUser ? theme.accent : theme.statusTints.running
        let isExpanded = expanded.contains(entry.id)
        let isLong = entry.text.count > 280 || entry.text.split(separator: "\n").count > Self.collapsedLineLimit

        return VStack(alignment: .leading, spacing: 6) {
            Text(Self.rendered(entry.text))
                .font(.islandText(size: 11.5))
                .foregroundStyle(V6Palette.paper.opacity(0.92))
                .lineLimit(isExpanded ? nil : Self.collapsedLineLimit)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if isLong {
                Button(isExpanded ? lang.t("conversation.showLess") : lang.t("conversation.showAll")) {
                    if isExpanded { expanded.remove(entry.id) } else { expanded.insert(entry.id) }
                }
                .buttonStyle(.plain)
                .font(.islandMono(size: 9.5, weight: .semibold))
                .foregroundStyle(tint)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(shape.fill(isUser ? tint.opacity(0.12) : V6Palette.ink.opacity(0.85)))
        .overlay(shape.stroke(SAOGrammar.Palette.hairline, lineWidth: 1))
        .overlay(shape.inset(by: 1).stroke(tint.opacity(0.35), lineWidth: 0.75))
        .frame(maxWidth: 330, alignment: isUser ? .trailing : .leading)
    }

    /// What the agent reached for — the tool's name and, for file tools, just
    /// the file's name. Never the input, never the output.
    private func toolLine(name: String, target: String?) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "chevron.right.2")
                .font(.system(size: 7, weight: .bold))
            Text(name)
                .font(.islandMono(size: 9.5, weight: .semibold))
            if let target {
                Text(target)
                    .font(.islandMono(size: 9.5))
                    .foregroundStyle(V6Palette.paper.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .foregroundStyle(theme.statusTints.running.opacity(0.75))
        .padding(.leading, 6)
    }

    private func notice(_ text: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .light))
            Text(text)
                .font(.islandText(size: 11.5))
        }
        .foregroundStyle(V6Palette.paper.opacity(0.45))
        .frame(maxWidth: .infinity, minHeight: Self.logHeight)
    }

    // MARK: - Loading

    private func load() async {
        // A session mid-answer updates several times a second. `.task(id:)`
        // cancels the previous run on each change, so waiting here first means
        // a burst of updates costs one read at the end of it rather than one
        // read per update. Skipped on the first load, which has nothing to
        // coalesce and should put the log on screen at once.
        if hasLoaded {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
        }
        guard let path = session?.claudeMetadata?.transcriptPath else {
            days = []
            hasLoaded = true
            return
        }
        let loaded = await Task.detached(priority: .utility) {
            ConversationLog.days(ConversationLog.read(path: path))
        }.value
        guard !Task.isCancelled else { return }
        if loaded != days { days = loaded }
        hasLoaded = true
    }

    /// Light Markdown only — bold, code, links — and plain text when it
    /// doesn't parse, so a stray asterisk never swallows a message.
    private static func rendered(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
