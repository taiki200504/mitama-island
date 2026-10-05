import Foundation
import OpenIslandCore

/// The three screens shown once, on a genuinely first launch.
///
/// No paywall and no licence entry — the reference product's two commercial
/// screens have no counterpart here, and inventing something to fill the gap
/// would only lengthen the thing standing between the user and the app.
enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome
    case detection
    case finish

    var id: Int { rawValue }

    var titleKey: String { "onboarding.\(name).title" }
    var bodyKey: String { "onboarding.\(name).body" }
    var symbolName: String {
        switch self {
        case .welcome: "circle.hexagongrid.fill"
        case .detection: "magnifyingglass"
        case .finish: "checkmark.seal.fill"
        }
    }

    private var name: String {
        switch self {
        case .welcome: "welcome"
        case .detection: "detection"
        case .finish: "finish"
        }
    }

    var isLast: Bool { self == Self.allCases.last }
}

/// Where the user is in the sequence, and what the buttons should say.
///
/// A plain value type so the order, the edges and the skip rule can be tested
/// without standing up a window.
struct OnboardingFlow: Equatable, Sendable {
    private(set) var step: OnboardingStep = .welcome

    var canGoBack: Bool { step != OnboardingStep.allCases.first }
    var isFinished = false

    var progressText: String {
        "\(step.rawValue + 1)/\(OnboardingStep.allCases.count)"
    }

    mutating func advance() {
        guard !step.isLast else {
            isFinished = true
            return
        }
        step = OnboardingStep(rawValue: step.rawValue + 1) ?? step
    }

    mutating func goBack() {
        guard canGoBack else { return }
        step = OnboardingStep(rawValue: step.rawValue - 1) ?? step
    }

    /// Skipping is finishing. Someone who skips has decided; showing them the
    /// same three screens next launch would read as the app not listening.
    mutating func skip() {
        isFinished = true
    }
}

/// Only a valid answer to the local practice question completes the exercise.
/// This value has no agent, SDK, bridge, or session-state dependency.
struct OnboardingPractice: Equatable, Sendable {
    static let answerKey = "onboarding-practice"
    private(set) var isComplete = false

    mutating func answer(_ response: QuestionPromptResponse, allowedAnswers: [String]) {
        guard let answer = response.answers[Self.answerKey], !answer.isEmpty,
              allowedAnswers.contains(answer) else { return }
        isComplete = true
    }
}
