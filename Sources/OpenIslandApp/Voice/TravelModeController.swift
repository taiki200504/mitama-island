import AppKit
import Foundation
import IOBluetooth
import OpenIslandCore
import os

private struct TravelCommand: Decodable, Sendable {
    let desired_enabled: Bool
    let revision: Int
}

private struct TravelSnapshot: Codable, Sendable {
    let address: String
    let wasConnected: Bool
}

private enum TravelFailure: String, Error {
    case targetMissing = "target_missing"
    case targetAmbiguous = "target_ambiguous"
    case bluetoothUnavailable = "bluetooth_unavailable"
    case disconnectFailed = "disconnect_failed"
    case reconnectFailed = "reconnect_failed"
    case localStateInvalid = "local_state_invalid"
}

/// Bluetooth objects never cross isolation boundaries. Only a paired, locally pinned address is used.
private enum TravelBluetooth {
    struct Target: Sendable { let address: String; let connected: Bool }
    static func target(pinned: String?) async throws -> Target {
        try await Task.detached {
            guard IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON else {
                throw TravelFailure.bluetoothUnavailable
            }
            let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
            let matches = paired.filter { device in
                if let pinned { return device.addressString == pinned }
                let name = (device.name ?? "").lowercased().filter { $0.isLetter || $0.isNumber }
                return ["opencomm2", "shokzopencomm2", "opencomm2byshokz", "opencomm2uc"].contains(name)
            }
            guard !matches.isEmpty else { throw TravelFailure.targetMissing }
            guard matches.count == 1, let address = matches[0].addressString else { throw TravelFailure.targetAmbiguous }
            return Target(address: address, connected: matches[0].isConnected())
        }.value
    }
    static func setConnected(_ connected: Bool, address: String) async throws {
        try await Task.detached {
            // Recheck pairing before each operation; no pairing, deletion, global toggle, or shell.
            let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
            guard let device = paired.first(where: { $0.addressString == address }) else { throw TravelFailure.targetMissing }
            guard device.isConnected() != connected else { return }
            let result = connected ? device.openConnection() : device.closeConnection()
            guard result == kIOReturnSuccess, device.isConnected() == connected else {
                throw connected ? TravelFailure.reconnectFailed : TravelFailure.disconnectFailed
            }
        }.value
    }
}

// Tokens are installed once on the main actor and only removed at destruction.
private final class TravelObserverTokens: @unchecked Sendable {
    var values: [NSObjectProtocol] = []
    deinit { for value in values { NSWorkspace.shared.notificationCenter.removeObserver(value) } }
}

/// Independent of agent execution and keep-awake policy. Persistent recovery state is written BEFORE cutting Bluetooth.
@MainActor
final class TravelModeController {
    private static let logger = Logger(subsystem: "com.mitama.island", category: "travel-mode")
    private let session: AmbientListenSession
    private let network: URLSession
    private let stateURL: URL
    private var snapshot: TravelSnapshot?
    private var stateInvalid = false
    private var task: Task<Void, Never>?
    private let observers = TravelObserverTokens()
    private var sleeping = false
    private var lastConnection = "unknown"

    init(session: AmbientListenSession, network: URLSession = .shared, stateURL: URL? = nil) {
        self.session = session
        self.network = network
        self.stateURL = stateURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/mitama-island/travel-mode.json")
        if FileManager.default.fileExists(atPath: self.stateURL.path) {
            do { snapshot = try JSONDecoder().decode(TravelSnapshot.self, from: Data(contentsOf: self.stateURL)) }
            catch { stateInvalid = true }
        }
        // A relaunch while offline must not restart the suspended microphone.
        if snapshot != nil || stateInvalid { session.setTravelSuspended(true) }
    }
    deinit {
        task?.cancel()
    }

    func start(deviceID: String) {
        guard task == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers.values.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sleeping = true }
        })
        observers.values.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sleeping = false }
        })
        task = Task { [weak self] in
            while !Task.isCancelled {
                if let self { await self.tick(deviceID: deviceID) } else { return }
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }

    private func tick(deviceID: String) async {
        guard let environment = MitamaEnvironment.load() else { return }
        do {
            // Only this installed Mac can enroll, using the existing server credential.
            // Ignore duplicate rows so a heartbeat cannot overwrite a phone's pending intent.
            _ = try await request(environment, method: "POST", query: [], body: [
                "device_id": deviceID, "label": Host.current().localizedName ?? "Mac"
            ], prefer: "resolution=ignore-duplicates")
            let data = try await request(environment, method: "GET", query: [
                URLQueryItem(name: "device_id", value: "eq.\(deviceID)"),
                URLQueryItem(name: "select", value: "desired_enabled,revision")
            ])
            guard let command = try JSONDecoder().decode([TravelCommand].self, from: data).first else { return }
            if sleeping {
                try await report(environment, deviceID: deviceID, revision: command.revision, phase: "ready", error: nil, acknowledged: false)
                return
            }
            try await report(environment, deviceID: deviceID, revision: command.revision, phase: "applying", error: nil, acknowledged: false)
            do {
                guard !stateInvalid else { throw TravelFailure.localStateInvalid }
                if command.desired_enabled {
                    let target = try await TravelBluetooth.target(pinned: snapshot?.address)
                    if snapshot == nil {
                        let saved = TravelSnapshot(address: target.address, wasConnected: target.connected)
                        try persist(saved)
                        snapshot = saved
                    }
                    session.setTravelSuspended(true)
                    try await TravelBluetooth.setConnected(false, address: target.address)
                    lastConnection = "disconnected"
                } else if let saved = snapshot {
                    // Restore only a connection this mode actually took away.
                    if saved.wasConnected { try await TravelBluetooth.setConnected(true, address: saved.address) }
                    let target = try await TravelBluetooth.target(pinned: saved.address)
                    lastConnection = target.connected ? "connected" : "disconnected"
                    try FileManager.default.removeItem(at: stateURL)
                    snapshot = nil
                    session.setTravelSuspended(false)
                } else {
                    // OFF after an unexecuted ON never connects anything.
                    let target = try? await TravelBluetooth.target(pinned: nil)
                    lastConnection = target.map { $0.connected ? "connected" : "disconnected" } ?? "unknown"
                    session.setTravelSuspended(false)
                }
                try await report(environment, deviceID: deviceID, revision: command.revision, phase: "applied", error: nil, acknowledged: true)
            } catch {
                lastConnection = "unknown"
                let code = (error as? TravelFailure)?.rawValue ?? TravelFailure.localStateInvalid.rawValue
                try await report(environment, deviceID: deviceID, revision: command.revision, phase: "error", error: code, acknowledged: false)
            }
        } catch {
            // No URLs, payloads or credential material in logs. An old heartbeat expires in the PWA.
            Self.logger.notice("travel mode sync unavailable")
        }
    }

    private func persist(_ value: TravelSnapshot) throws {
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: stateURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
    }

    private func report(_ environment: MitamaEnvironment, deviceID: String, revision: Int, phase: String, error: String?, acknowledged: Bool) async throws {
        var body: [String: Any] = [
            "applied_enabled": snapshot != nil, "connection": lastConnection,
            "power_state": sleeping ? "sleeping" : "awake", "phase": phase,
            "last_seen_at": Date().ISO8601Format(), "error_code": error.map { $0 as Any } ?? NSNull()
        ]
        if acknowledged { body["reported_revision"] = revision }
        // Compare-and-set: a result for old ON must not acknowledge a newer OFF.
        _ = try await request(environment, method: "PATCH", query: [
            URLQueryItem(name: "device_id", value: "eq.\(deviceID)"),
            URLQueryItem(name: "revision", value: "eq.\(revision)")
        ], body: body)
    }

    private func request(_ environment: MitamaEnvironment, method: String, query: [URLQueryItem], body: [String: Any]? = nil, prefer: String? = nil) async throws -> Data {
        var parts = URLComponents(url: environment.url.appendingPathComponent("rest/v1/mos_travel_devices"), resolvingAgainstBaseURL: false)
        parts?.queryItems = query.isEmpty ? nil : query
        guard let url = parts?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await network.data(for: environment.authorized(request))
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else { throw URLError(.badServerResponse) }
        return data
    }
}
