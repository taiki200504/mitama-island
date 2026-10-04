import Combine
import Foundation
import Sparkle

/// Wraps Sparkle's `SPUUpdater` to provide observable update state for SwiftUI.
///
/// Sparkle handles the full lifecycle: checking for updates, downloading,
/// extracting, replacing the app bundle, and relaunching.
/// This wrapper simply exposes the current state so the UI can react.
@MainActor
@Observable
final class UpdateChecker: NSObject {
    static let releasesURL = URL(string: "https://github.com/Octane0411/open-vibe-island/releases")!

    private(set) var canCheckForUpdates = false
    private(set) var hasUpdate = false
    private(set) var latestVersion: String?

    @ObservationIgnored
    private var updaterController: SPUStandardUpdaterController?

    let isEnabled: Bool
    @ObservationIgnored private var started = false

    @ObservationIgnored
    private var cancellable: AnyCancellable?

    override convenience init() {
        self.init(feedURL: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String)
    }

    init(feedURL: String?) {
        isEnabled = Self.validFeedURL(feedURL) != nil
        super.init()
        guard isEnabled else { return }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    static func validFeedURL(_ text: String?) -> URL? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, let url = URL(string: text), url.scheme == "https",
              url.host?.isEmpty == false, url.user == nil, url.password == nil,
              url.fragment == nil else { return nil }
        return url
    }

    /// Local bundles carry no feed and never start Sparkle, in any build configuration.
    func startIfNeeded() {
        guard isEnabled, !started, let updater = updaterController?.updater else { return }
        updater.automaticallyChecksForUpdates = Bundle.main.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool ?? false
        updater.updateCheckInterval = 60 * 60
        updater.automaticallyDownloadsUpdates = false
        do {
            try updater.start()
            started = true
        } catch {
            print("[UpdateChecker] Failed to start Sparkle updater: \(error)")
            return
        }
        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
    }

    func checkForUpdates() {
        guard isEnabled, canCheckForUpdates else { return }
        updaterController?.checkForUpdates(nil)
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdateChecker: SPUUpdaterDelegate {
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        Set()
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in
            guard self.isEnabled else { return }
            self.hasUpdate = true
            self.latestVersion = version
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        Task { @MainActor in
            self.hasUpdate = false
            self.latestVersion = nil
        }
    }
}
