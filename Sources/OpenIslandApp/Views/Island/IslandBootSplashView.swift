import SwiftUI

/// What the opened island shows for the one second after launch, before
/// falling through to whatever `fallback` would have shown anyway.
///
/// `performBootAnimation()` only holds the panel open for 1.5s total, so
/// this is deliberately short: the ring's own 1.0s run leaves just enough
/// of that window for the ordinary content to be visible for a moment
/// before the panel closes itself.
struct IslandBootSplashView<Fallback: View>: View {
    @ViewBuilder var fallback: () -> Fallback

    @State private var ringProgress: Double = 0
    @State private var isFinished = false
    @State private var finishTask: Task<Void, Never>?

    /// Fixed, not localized — a system readout rather than a sentence, the
    /// same treatment `V6PeekBandView` gives an agent's own name.
    private let label = "SYSTEM ONLINE"

    var body: some View {
        if isFinished {
            fallback()
        } else {
            VStack(spacing: 14) {
                Spacer(minLength: 0)
                SAORingView(progress: ringProgress, tint: IslandThemes.current.accent)
                    .frame(width: 60, height: 60)
                Text(label)
                    .saoCaps(size: 11)
                    .foregroundStyle(V6Palette.paper.opacity(0.62))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .onAppear {
                withAnimation(.linear(duration: 1.0)) {
                    ringProgress = 1
                }
                // A plain `asyncAfter` would still fire and flip `isFinished`
                // even after this view (and its `@State`) is gone — the
                // panel can close well inside 1.0s if the user acts first.
                finishTask = Task {
                    try? await Task.sleep(for: .seconds(1.0))
                    guard !Task.isCancelled else { return }
                    isFinished = true
                }
            }
            .onDisappear {
                finishTask?.cancel()
                finishTask = nil
            }
        }
    }
}
