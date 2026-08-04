import SwiftUI

/// The one-time introduction. Five screens, no purchase, skippable throughout.
struct OnboardingView: View {
    var model: AppModel
    @State private var flow = OnboardingFlow()

    private var lang: LanguageManager { model.lang }

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            controls
        }
        .frame(width: 520, height: 400)
        .onChange(of: flow.isFinished) { _, finished in
            guard finished else { return }
            model.completeOnboarding()
        }
    }

    private var content: some View {
        VStack(spacing: 18) {
            Image(systemName: flow.step.symbolName)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text(lang.t(flow.step.titleKey))
                .font(.system(size: 21, weight: .semibold))
                .multilineTextAlignment(.center)

            Text(detailText)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)

            Spacer(minLength: 0)
        }
        .padding(.top, 44)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The detection screen reports what is actually on this Mac rather than
    /// listing every agent the app could in principle talk to.
    private var detailText: String {
        let body = lang.t(flow.step.bodyKey)
        guard flow.step == .detection else { return body }
        let found = model.installedAgentDisplayNames
        return body.replacingOccurrences(
            of: "{agents}",
            with: found.isEmpty ? lang.t("onboarding.detection.none") : found.joined(separator: ", ")
        )
    }

    private var controls: some View {
        HStack {
            Button(lang.t("onboarding.skip")) { flow.skip() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            Spacer()

            Text(flow.progressText)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            if flow.canGoBack {
                Button(lang.t("onboarding.back")) { flow.goBack() }
            }

            Button(lang.t(flow.step.isLast ? "onboarding.finish" : "onboarding.next")) {
                flow.advance()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
