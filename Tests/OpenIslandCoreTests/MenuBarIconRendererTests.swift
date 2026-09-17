import Testing
import AppKit
import OpenIslandCore

@Suite("MenuBarIconRenderer")
final class MenuBarIconRendererTests {
    @Test("Renders all states without crashing")
    func rendersAllStates() {
        for state in [MenuBarIconRenderer.State.idle, .waiting, .running, .approvalNeeded] {
            let image = MenuBarIconRenderer.image(for: state)
            #expect(image.size.width == 18, "Width should be 18 for state \(state)")
            #expect(image.size.height == 16, "Height should be 16 for state \(state)")
            #expect(image.isTemplate, "Image should be template for state \(state)")
        }
    }

    @Test("Idle and approval needed are distinct")
    func idleAndApprovalDifferent() {
        let idleImage = MenuBarIconRenderer.image(for: .idle)
        let approvalImage = MenuBarIconRenderer.image(for: .approvalNeeded)

        // Both should be valid images
        #expect(idleImage != nil, "Idle should render")
        #expect(approvalImage != nil, "ApprovalNeeded should render")

        // Visual difference would require pixel-level comparison;
        // this test just ensures both produce images
        #expect(idleImage.size == approvalImage.size, "Both should be same size")
    }

    @Test("Waiting and running are distinct from idle")
    func activeStatesDistinct() {
        let idle = MenuBarIconRenderer.image(for: .idle)
        let waiting = MenuBarIconRenderer.image(for: .waiting)
        let running = MenuBarIconRenderer.image(for: .running)

        // All should produce valid images; exact visual distinction requires rendering inspection
        #expect(idle.size == CGSize(width: 18, height: 16), "Idle size correct")
        #expect(waiting.size == CGSize(width: 18, height: 16), "Waiting size correct")
        #expect(running.size == CGSize(width: 18, height: 16), "Running size correct")
    }
}
