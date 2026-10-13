import CryptoKit
import Foundation
import IOKit
import OpenIslandCore
import os

struct EarshotRemoteCommand: Decodable, Equatable {
    let listen_command: Bool?
    let command_at: String?

    /// A replay, including after relaunch or a local switch, must not win again.
    func applicable(after savedAt: Double) -> (enabled: Bool, at: Double)? {
        guard let enabled = listen_command, let text = command_at else { return nil }
        let fractional = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text)
        let wholeSeconds = try? Date.ISO8601FormatStyle().parse(text)
        guard let date = fractional ?? wholeSeconds,
              date.timeIntervalSince1970 > savedAt else { return nil }
        return (enabled, date.timeIntervalSince1970)
    }
}

@MainActor
final class EarshotDeviceReporter {
    private static let logger = Logger(subsystem: "com.mitama.island", category: "earshot-device")
    private let session: AmbientListenSession
    private let settings: AmbientListenSettings
    private let network: URLSession
    private let deviceID: String?
    private var task: Task<Void, Never>?

    init(session: AmbientListenSession, settings: AmbientListenSettings, network: URLSession = .shared) {
        self.session = session
        self.settings = settings
        self.network = network
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            let uuid = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            deviceID = uuid.map { String(SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16)) }
        } else {
            deviceID = nil
        }
    }

    deinit { task?.cancel() }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            var lastReport = Date.distantPast
            var previousPhase: AmbientListenSession.Phase?
            var previousEnabled: Bool?
            var phaseChangedAt: Date?
            while !Task.isCancelled {
                if let self {
                    let now = Date()
                    if previousPhase != self.session.phase {
                        previousPhase = self.session.phase
                        phaseChangedAt = now
                    }
                    let enabledChanged = previousEnabled != self.settings.isEnabled
                    previousEnabled = self.settings.isEnabled
                    if enabledChanged || now.timeIntervalSince(lastReport) >= 60 ||
                        phaseChangedAt.map({ now.timeIntervalSince($0) >= 5 }) == true {
                        lastReport = now
                        phaseChangedAt = nil
                        await self.report()
                    }
                } else { return }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    static func pendingFiles(in directory: URL) -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return 0 }
        let names = Set(files)
        return files.filter { name in
            guard name.hasSuffix(".wav"), !names.contains(name + ".done") else { return false }
            return (try? directory.appendingPathComponent(name).resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
        }.count
    }

    func statusBody(deviceID: String, now: Date = .now) -> [String: Any] {
        let phase: String
        if !settings.isEnabled {
            phase = "off"
        } else {
            switch session.phase {
            case .idle: phase = "idle"
            case .listening: phase = "recording"
            case .pausedForCall: phase = "paused_call"
            case .denied, .unavailable: phase = "error"
            }
        }
        return [
            "device_id": deviceID,
            "kind": "mac",
            "label": Host.current().localizedName ?? "Mac",
            "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "last_seen_at": now.ISO8601Format(),
            "listening": settings.isEnabled,
            "phase": phase,
            "current_segment_s": session.currentSegmentSeconds,
            "pending_files": Self.pendingFiles(in: AmbientListenSession.defaultDirectory),
            "updated_at": now.ISO8601Format(),
        ]
    }

    private func report() async {
        guard let deviceID, let environment = MitamaEnvironment.load() else {
            Self.logger.notice("device ID or credentials unavailable")
            return
        }
        do {
            try await upsert(environment: environment, deviceID: deviceID)
            var components = URLComponents(url: environment.url.appendingPathComponent("rest/v1/mos_devices"), resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "device_id", value: "eq.\(deviceID)"),
                URLQueryItem(name: "select", value: "listen_command,command_at"),
            ]
            guard let url = components?.url else { return }
            let data = try await send(environment.authorized(URLRequest(url: url, timeoutInterval: 15)))
            let commands = try JSONDecoder().decode([EarshotRemoteCommand].self, from: data)
            guard !Task.isCancelled, let command = commands.first?.applicable(after: settings.remoteCommandAt) else { return }
            settings.isEnabled = command.enabled
            session.settingsChanged()
            settings.remoteCommandAt = command.at
            try await upsert(environment: environment, deviceID: deviceID)
        } catch {
            // Do not log URLs, response bodies, or credentials.
            Self.logger.notice("device report failed")
        }
    }

    private func upsert(environment: MitamaEnvironment, deviceID: String) async throws {
        var request = URLRequest(url: environment.url.appendingPathComponent("rest/v1/mos_devices"), timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: statusBody(deviceID: deviceID))
        _ = try await send(environment.authorized(request))
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await network.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
