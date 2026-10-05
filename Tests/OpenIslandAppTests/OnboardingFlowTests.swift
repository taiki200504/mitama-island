import Testing
import OpenIslandCore
@testable import OpenIslandApp

@Suite("Onboarding flow")
struct OnboardingFlowTests {
    @Test("Three screens, connection and practice")
    func threeSteps() {
        #expect(OnboardingStep.allCases == [.welcome, .detection, .finish])
        #expect(OnboardingStep.allCases.first == .welcome)
        #expect(OnboardingStep.allCases.last == .finish)
    }

    @Test("Advancing walks the sequence once")
    func advances() {
        var flow = OnboardingFlow()
        var seen: [OnboardingStep] = [flow.step]
        while !flow.isFinished {
            flow.advance()
            if !flow.isFinished { seen.append(flow.step) }
        }
        #expect(seen == OnboardingStep.allCases)
    }

    @Test("The first screen has nowhere to go back to")
    func firstHasNoBack() {
        var flow = OnboardingFlow()
        #expect(flow.canGoBack == false)
        flow.goBack()
        #expect(flow.step == .welcome)
    }

    @Test("Back returns to the previous screen")
    func goesBack() {
        var flow = OnboardingFlow()
        flow.advance()
        flow.goBack()
        #expect(flow.step == .welcome)
    }

    /// Skipping has to count as finishing. Otherwise the same three screens
    /// appear again next launch, which reads as the app ignoring the user.
    @Test("Skipping finishes the flow")
    func skipFinishes() {
        var flow = OnboardingFlow()
        flow.skip()
        #expect(flow.isFinished)
    }

    @Test("Progress counts from one")
    func progressText() {
        var flow = OnboardingFlow()
        #expect(flow.progressText == "1/3")
        flow.advance()
        #expect(flow.progressText == "2/3")
    }

    /// Advancing past the end must finish rather than fall off the sequence.
    @Test("The last screen finishes instead of advancing")
    func lastFinishes() {
        var flow = OnboardingFlow()
        for _ in 0..<2 { flow.advance() }
        #expect(flow.step == .finish)
        #expect(flow.isFinished == false)
        flow.advance()
        #expect(flow.isFinished)
        #expect(flow.step == .finish)
    }
    @Test("Only the local practice question's offered answers complete practice")
    func localPracticeValidatesAnswer() {
        var practice = OnboardingPractice()
        practice.answer(.init(answers: ["another-question": "A"]), allowedAnswers: ["A", "B"])
        #expect(!practice.isComplete)
        practice.answer(.init(answers: [OnboardingPractice.answerKey: "unknown"]), allowedAnswers: ["A", "B"])
        #expect(!practice.isComplete)
        practice.answer(.init(answers: [OnboardingPractice.answerKey: "B"]), allowedAnswers: ["A", "B"])
        #expect(practice.isComplete)
    }

}
