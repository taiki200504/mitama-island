import AppKit
import SwiftUI

@MainActor
final class OpenIslandAppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private let harnessLaunchConfiguration = HarnessLaunchConfiguration()
    private let launchedAt = Date()
    private lazy var harnessRuntimeMonitor = HarnessRuntimeMonitor(launchedAt: launchedAt)

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination(
            "Open Island should remain active while monitoring local agent sessions."
        )
        ProcessInfo.processInfo.disableSuddenTermination()
        NSApp.setActivationPolicy(model.showDockIcon ? .regular : .accessory)
        harnessRuntimeMonitor.recordMilestone("applicationDidFinishLaunching")

        DispatchQueue.main.async { [self] in
            harnessRuntimeMonitor.recordMilestone("bootstrapStarted")
            model.harnessRuntimeMonitor = harnessRuntimeMonitor
            harnessRuntimeMonitor.recordLog(model.lastActionMessage)

            model.ignoresPointerExitDuringHarness = harnessLaunchConfiguration.scenario != nil
            model.disablesOverlayEventMonitoringDuringHarness = harnessLaunchConfiguration.scenario != nil
            model.startIfNeeded(
                startBridge: harnessLaunchConfiguration.shouldStartBridge,
                shouldPerformBootAnimation: harnessLaunchConfiguration.shouldPerformBootAnimation,
                loadRuntimeState: harnessLaunchConfiguration.scenario == nil
            )
            harnessRuntimeMonitor.recordMilestone("modelStarted")

            // Hide all windows on launch — settings opens on demand only.
            // Before the scenario loads, not after: a scenario that puts up a
            // panel of its own would otherwise have it swept away again, which
            // is exactly what happened to the completion banner.
            OpenIslandAppDelegate.hideAllAppWindows()

            if let scenario = harnessLaunchConfiguration.scenario {
                model.loadDebugSnapshot(
                    scenario.snapshot(),
                    presentOverlay: harnessLaunchConfiguration.presentOverlay
                )
            }

            // Never during a harness run: an introduction window would sit on
            // top of every screenshot the capture scripts take.
            if model.needsOnboarding, harnessLaunchConfiguration.scenario == nil {
                model.presentOnboarding?()
            }

            // The recorder captures every visible window, so opening settings on
            // the requested pane is all it takes to get a shot of that pane.
            if let tab = harnessLaunchConfiguration.settingsTab {
                model.showSettings(tab: tab)
                harnessRuntimeMonitor.recordMilestone("settingsOpened", message: tab)
            }

            harnessRuntimeMonitor.recordMilestone("bootstrapCompleted")

            if let captureDelay = harnessLaunchConfiguration.captureDelay,
               harnessLaunchConfiguration.artifactDirectoryURL != nil {
                harnessRuntimeMonitor.recordMilestone(
                    "captureScheduled",
                    message: String(format: "%.3fs", captureDelay)
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + captureDelay) { [self] in
                    harnessRuntimeMonitor.recordMilestone("captureStarted")
                    try? HarnessArtifactRecorder.record(
                        configuration: harnessLaunchConfiguration,
                        model: model,
                        launchedAt: launchedAt,
                        runtimeMonitor: harnessRuntimeMonitor
                    )
                }
            }

            if let autoExitAfter = harnessLaunchConfiguration.autoExitAfter {
                harnessRuntimeMonitor.recordMilestone(
                    "autoExitScheduled",
                    message: String(format: "%.3fs", autoExitAfter)
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + autoExitAfter) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private static func hideAllAppWindows() {
        for window in NSApp.windows {
            window.orderOut(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.showSettings()
        return false
    }
}

@main
struct OpenIslandApp: App {
    @NSApplicationDelegateAdaptor(OpenIslandAppDelegate.self)
    private var appDelegate

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Open Island Settings", id: "settings") {
            SettingsWindowContent(model: appDelegate.model)
        }
        .windowResizability(.contentMinSize)

        Window("Welcome", id: "onboarding") {
            OnboardingWindowContent(model: appDelegate.model)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    openWindow(id: "settings")
                    appDelegate.model.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

/// Refreshes the `openWindow` registration each time the settings
/// window opens, keeping the closure current after window recreation.
private struct OnboardingWindowContent: View {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        OnboardingView(model: model)
            .onAppear {
                model.presentOnboarding = { [openWindow] in openWindow(id: "onboarding") }
                model.closeOnboardingWindow = { [dismissWindow] in dismissWindow(id: "onboarding") }
            }
    }
}

private struct SettingsWindowContent: View {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SettingsView(model: model)
            .onAppear {
                model.openSettingsWindow = { [openWindow] in
                    openWindow(id: "settings")
                }
            }
    }
}
