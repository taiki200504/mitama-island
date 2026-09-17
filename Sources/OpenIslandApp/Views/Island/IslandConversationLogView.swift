import SwiftUI
import OpenIslandCore

struct IslandConversationLogView: View {
    let session: AgentSession
    let lang: LanguageManager
    var onDismiss: (() -> Void)?

    @State private var messages: [ConversationMessage] = []
    @State private var isLoading = true
    @State private var scrollProxy: ScrollViewReader?
    @Environment(\.colorScheme) var colorScheme

    private var claudeMetadata: ClaudeSessionMetadata? {
        session.claudeSessionMetadata
    }

    private var transcriptPath: String? {
        claudeMetadata?.transcriptPath
    }

    private var isQuiet: Bool {
        // Hide message text during screen sharing or other "quiet" times
        false // TODO: integrate with existing quietScenes logic
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text("CONVERSATION")
                    .saoCaps(size: 11, weight: .semibold)
                    .foregroundStyle(V6Palette.paper.opacity(0.6))
                Spacer()
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(V6Palette.paper.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(V6Palette.paper.opacity(0.045))
                    .frame(height: 1)
            }

            // Message list
            if isLoading {
                VStack {
                    Spacer()
                    Text("Loading…")
                        .font(.islandText(size: 12))
                        .foregroundStyle(V6Palette.paper.opacity(0.5))
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else if messages.isEmpty {
                VStack {
                    Spacer()
                    Text("No messages yet")
                        .font(.islandText(size: 12))
                        .foregroundStyle(V6Palette.paper.opacity(0.5))
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 8) {
                            let groups = messages.groupedByConsecutiveRole()
                            let boundaries = messages.dayBoundaries()

                            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                                // Day separator before this group if needed
                                if let boundary = boundaries.first(where: { $0.messageIndex <= group.messages.first?.timestamp.timeIntervalSince1970 ?? 0 }) {
                                    VStack(spacing: 0) {
                                        Rectangle()
                                            .fill(V6Palette.paper.opacity(0.1))
                                            .frame(height: 1)
                                        Text(formatDate(boundary.date))
                                            .font(.islandMono(size: 10))
                                            .foregroundStyle(V6Palette.paper.opacity(0.4))
                                            .padding(.vertical, 4)
                                        Rectangle()
                                            .fill(V6Palette.paper.opacity(0.1))
                                            .frame(height: 1)
                                    }
                                    .padding(.vertical, 4)
                                }

                                messageGroupView(group)
                                    .id("msg_\(index)")
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.hidden)
                    .onAppear {
                        scrollProxy = proxy
                        if let lastGroup = messages.groupedByConsecutiveRole().last {
                            scrollToLast()
                        }
                    }
                }
                .frame(height: 300) // Fixed max height
            }
        }
        .frame(maxWidth: .infinity)
        .background(V6Palette.ink)
        .onAppear { loadMessages() }
    }

    // MARK: - Subviews

    private func messageGroupView(_ group: ConversationMessageGroup) -> some View {
        VStack(alignment: group.role == .user ? .trailing : .leading, spacing: 4) {
            ForEach(group.messages) { message in
                messageBubble(message, isUser: group.role == .user)
            }
        }
        .frame(maxWidth: .infinity, alignment: group.role == .user ? .trailing : .leading)
    }

    private func messageBubble(_ message: ConversationMessage, isUser: Bool) -> some View {
        let displayText = isQuiet && !isUser ? "..." : message.text
        let bubbleColor = isUser
            ? SAOGrammar.Palette.accentOrange.opacity(0.15)
            : V6Palette.paper.opacity(0.08)

        return VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            if let toolSummary = message.toolSummary, !toolSummary.isEmpty {
                Text(toolSummary)
                    .font(.islandMono(size: 10))
                    .foregroundStyle(V6Palette.paper.opacity(0.5))
            }

            if !displayText.isEmpty {
                Text(displayText)
                    .font(.islandText(size: 11))
                    .foregroundStyle(V6Palette.paper.opacity(isQuiet && !isUser ? 0.3 : 0.9))
                    .lineLimit(nil)
                    .multilineTextAlignment(isUser ? .trailing : .leading)
            }

            Text(formatTime(message.timestamp))
                .font(.islandMono(size: 9))
                .foregroundStyle(V6Palette.paper.opacity(0.3))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            IslandThemes.current.shape(cornerRadius: 6)
                .fill(bubbleColor)
                .overlay(
                    IslandThemes.current.shape(cornerRadius: 6)
                        .stroke(
                            (isUser ? SAOGrammar.Palette.accentOrange : V6Palette.paper)
                                .opacity(0.15),
                            lineWidth: 0.5
                        )
                )
        )
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    // MARK: - Loading & Formatting

    private func loadMessages() {
        Task {
            defer { isLoading = false }
            guard let path = transcriptPath else { return }
            messages = ConversationLogReader.readMessages(
                from: path,
                maxMessages: 200,
                maxFileSize: 8 * 1024 * 1024
            )
        }
    }

    private func scrollToLast() {
        let groups = messages.groupedByConsecutiveRole()
        if let lastIndex = groups.indices.last {
            scrollProxy?.scrollTo("msg_\(lastIndex)", anchor: .bottom)
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

#Preview {
    let session = AgentSession(
        id: "test-session",
        agentType: "claude",
        displayName: "Claude Code",
        phase: .idle,
        startedAt: Date()
    )
    var metadata = ClaudeSessionMetadata()
    metadata.transcriptPath = "/tmp/test-transcript.jsonl"

    return IslandConversationLogView(
        session: session,
        lang: .shared
    )
    .frame(width: 400, height: 400)
    .background(V6Palette.ink)
}
