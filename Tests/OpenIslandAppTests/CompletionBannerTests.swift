import Foundation
import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

@Suite("Completion duration")
struct CompletionDurationFormatterTests {
    /// "0秒" reads as a failure rather than a fast task, so very short runs say
    /// nothing at all about their length.
    @Test("A near-instant run reports no duration")
    func skipsTrivialDurations() {
        #expect(CompletionDurationFormatter.string(for: 0) == nil)
        #expect(CompletionDurationFormatter.string(for: 2.4) == nil)
    }

    @Test("Seconds, minutes and hours each get their own shape")
    func formatsEachScale() {
        #expect(CompletionDurationFormatter.string(for: 12) == "12秒")
        #expect(CompletionDurationFormatter.string(for: 252) == "4分12秒")
        #expect(CompletionDurationFormatter.string(for: 7_500) == "2時間5分")
    }

    @Test("The boundary between scales is clean")
    func boundaries() {
        #expect(CompletionDurationFormatter.string(for: 59) == "59秒")
        #expect(CompletionDurationFormatter.string(for: 60) == "1分0秒")
        #expect(CompletionDurationFormatter.string(for: 3_600) == "1時間0分")
    }

    @Test("A run of exactly the cutoff still reports")
    func cutoffIsInclusive() {
        #expect(CompletionDurationFormatter.string(for: 3) == "3秒")
    }
}

@Suite("Completion banner", .serialized)
@MainActor
struct CompletionBannerControllerTests {
    private let content = CompletionBannerContent(
        sessionID: "s1",
        title: "mitama-island",
        agentName: "Claude Code",
        duration: "4分12秒"
    )

    @Test("Presenting puts a window up, dismissing takes it away")
    func presentsAndDismisses() {
        let controller = CompletionBannerController()
        controller.present(content, on: nil)
        #expect(controller.isPresenting)

        controller.dismiss()
        #expect(controller.isPresenting == false)
    }

    /// Two banners stacked in the middle of the screen would be worse than
    /// missing one, so a second completion replaces the first.
    @Test("A second completion replaces the first")
    func replacesRatherThanStacks() {
        let controller = CompletionBannerController()
        controller.present(content, on: nil)
        controller.present(content, on: nil)
        #expect(controller.isPresenting)
        controller.dismiss()
    }

    @Test("Dismissing twice is harmless")
    func idempotentDismiss() {
        let controller = CompletionBannerController()
        controller.dismiss()
        controller.dismiss()
        #expect(controller.isPresenting == false)
    }

    /// It sits under the notch rather than over the work. That position is what
    /// makes taking the mouse acceptable — the close button has to be clickable,
    /// and there is nothing to click through to up there.
    @Test("The banner hangs below the notch, not over the work")
    func sitsBelowTheNotch() throws {
        let controller = CompletionBannerController()
        controller.present(content, on: nil)
        defer { controller.dismiss() }

        let panel = try #require(
            NSApp.windows.first { $0.contentView is NSHostingView<CompletionBannerView> }
        )
        let screen = try #require(panel.screen ?? NSScreen.main)
        #expect(panel.frame.maxY <= screen.frame.maxY)
        // Well within the top quarter — nowhere near the middle of the screen.
        #expect(panel.frame.minY > screen.frame.maxY - screen.frame.height * 0.25)
    }

    /// Small on purpose. This is a notification, not a dialog.
    @Test("The banner stays small")
    func staysSmall() {
        #expect(CompletionBannerView.size.width <= 360)
        #expect(CompletionBannerView.size.height <= 70)
    }
}
