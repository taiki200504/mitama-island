import Foundation

/// One row of `mos_notifications` — the queue mitama posts to when it needs a
/// human. Only the fields the island renders are decoded.
public struct MitamaNotification: Codable, Equatable, Sendable, Identifiable {
    public enum Level: String, Codable, Sendable, CaseIterable {
        case urgent
        case homework
        case digest
        case info

        /// Levels worth interrupting for. `digest` and `info` are records, not
        /// requests, and there are hundreds of them — they belong in the Hub.
        public static let actionable: [Level] = [.urgent, .homework]
    }

    public let id: Int
    public let level: Level
    public let title: String
    public let body: String
    public let createdAt: Date

    public init(id: Int, level: Level, title: String, body: String, createdAt: Date) {
        self.id = id
        self.level = level
        self.title = title
        self.body = body
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case level
        case title
        case body
        case createdAt = "created_at"
    }
}

/// Supabase credentials.
///
/// Preferred source is the login keychain; the mitama-os `.env` stays as a
/// fallback so an existing setup keeps working while the key is moved across.
/// Never stored in this app's own preferences — one place to rotate, and not a
/// plaintext one.
public struct MitamaEnvironment: Equatable, Sendable {
    public let url: URL
    public let apiKey: String

    public static var defaultEnvFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Developer/mitama/mitama-os/.env")
    }

    /// Parses `KEY=value` lines. Values may be quoted; `export` prefixes and
    /// comments are tolerated because hand-edited .env files contain both.
    public static func parse(envFileContents contents: String) -> MitamaEnvironment? {
        var values: [String: String] = [:]

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") {
                line = String(line.dropFirst("export ".count))
            }
            guard let separatorIndex = line.firstIndex(of: "=") else { continue }

            let key = String(line[line.startIndex..<separatorIndex]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               let first = value.first,
               let last = value.last,
               first == last,
               first == "\"" || first == "'" {
                value = String(value.dropFirst().dropLast())
            }
            guard !key.isEmpty, !value.isEmpty else { continue }
            values[key] = value
        }

        guard let urlText = values["SUPABASE_URL"],
              let url = URL(string: urlText),
              let key = values["SUPABASE_KEY"] else {
            return nil
        }

        return MitamaEnvironment(url: url, apiKey: key)
    }

    /// Where a loaded credential came from, so the UI can say whether the key is
    /// still sitting in a plaintext file.
    public enum Source: Equatable, Sendable {
        case keychain
        case envFile
    }

    public static func load(from fileURL: URL = defaultEnvFileURL) -> MitamaEnvironment? {
        loadWithSource(from: fileURL)?.environment
    }

    public static func loadWithSource(
        from fileURL: URL = defaultEnvFileURL
    ) -> (environment: MitamaEnvironment, source: Source)? {
        if let fromKeychain = MitamaKeychain.environment() {
            return (fromKeychain, .keychain)
        }
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8),
              let parsed = parse(envFileContents: contents) else {
            return nil
        }
        return (parsed, .envFile)
    }

    /// The key goes into headers here and nowhere else, so every caller signs
    /// requests the same way and none of them has to hold the key to do it.
    public func authorized(_ request: URLRequest) -> URLRequest {
        var request = request
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    func endpoint(_ table: String, queryItems: [URLQueryItem] = []) -> URL? {
        var components = URLComponents(
            url: url.appendingPathComponent("rest/v1/\(table)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        return components?.url
    }
}

/// Reads and acknowledges mitama's notification queue over PostgREST.
///
/// The key never leaves this type: it goes into request headers and is never
/// logged, echoed in errors, or written to the island's own preferences.
public struct MitamaNotificationClient: Sendable {
    public enum ClientError: Error, LocalizedError {
        case requestFailed(status: Int)

        public var errorDescription: String? {
            switch self {
            case let .requestFailed(status):
                return "mitama notifications request failed (HTTP \(status))"
            }
        }
    }

    private let environment: MitamaEnvironment
    private let session: URLSession

    public init(environment: MitamaEnvironment, session: URLSession = .shared) {
        self.environment = environment
        self.session = session
    }

    /// Postgres renders `timestamptz` with a variable number of fractional
    /// digits, so both shapes have to be accepted. Formatters are built per
    /// decode rather than shared: `ISO8601DateFormatter` is not `Sendable`,
    /// and a handful of rows per minute does not justify the ceremony.
    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: text) {
                return date
            }
            if let date = ISO8601DateFormatter().date(from: text) {
                return date
            }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "unrecognised timestamp")
            )
        }
        return decoder
    }

    private func authorized(_ request: URLRequest) -> URLRequest {
        environment.authorized(request)
    }

    /// Unread rows at the levels that ask something of the reader, newest first.
    public func fetchActionable(limit: Int = 20) async throws -> [MitamaNotification] {
        let levels = MitamaNotification.Level.actionable.map(\.rawValue).joined(separator: ",")
        var components = URLComponents(
            url: environment.url.appendingPathComponent("rest/v1/mos_notifications"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "select", value: "id,level,title,body,created_at"),
            URLQueryItem(name: "read", value: "eq.false"),
            URLQueryItem(name: "level", value: "in.(\(levels))"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]

        guard let url = components?.url else {
            return []
        }

        let (data, response) = try await session.data(for: authorized(URLRequest(url: url)))
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw ClientError.requestFailed(status: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        return try decoder.decode([MitamaNotification].self, from: data)
    }

    /// Test hook: the timestamp handling is the fragile part of this type, and
    /// exercising it through a live request would prove nothing.
    func decodeForTests<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }

    public func markRead(id: Int) async throws {
        var components = URLComponents(
            url: environment.url.appendingPathComponent("rest/v1/mos_notifications"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "id", value: "eq.\(id)")]
        guard let url = components?.url else { return }

        var request = authorized(URLRequest(url: url))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = #"{"read":true}"#.data(using: .utf8)

        let (_, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw ClientError.requestFailed(status: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }
}
