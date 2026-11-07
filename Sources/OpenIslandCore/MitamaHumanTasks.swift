import Foundation

public struct MitamaHumanTask: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let body: String?
    public let resumeObjective: String?
    public let createdAt: Date
    /// grok-relay / dots-relay。古い行や欠けた列は Grok 扱い。
    public var source: String? = nil
    /// relay(Mac の Paseo) / dots-dispatch(アリス。振り分け役が拾うので島はジョブを積まない)
    public var resumeAgent: String? = nil
    public var originLabel: String { source == "dots-relay" ? "Dots" : "Grok" }

    enum CodingKeys: String, CodingKey {
        case id, title, body, source
        case resumeObjective = "resume_objective"
        case resumeAgent = "resume_agent"
        case createdAt = "created_at"
    }
}

/// Reads what is waiting. The island has a service key and no owner login, so it never answers a decision (v305): the owner
/// answers through `mos_human_answer` in the Hub, or in the signed-in Mac app.
public struct MitamaHumanTaskClient: Sendable {
    public enum ClientError: Error, LocalizedError {
        case invalidRequest, requestFailed(Int)
        public var errorDescription: String? {
            switch self {
            case .invalidRequest: "依頼の形式が正しくありません"
            case .requestFailed(let status): "判断待ちの通信に失敗しました (HTTP \(status))"
            }
        }
    }
    private let environment: MitamaEnvironment
    private let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(environment: MitamaEnvironment, session: URLSession = .shared) {
        self.environment = environment
        transport = { try await session.data(for: $0) }
    }

    init(environment: MitamaEnvironment, transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        self.environment = environment
        self.transport = transport
    }

    public func fetchOpen() async throws -> [MitamaHumanTask] {
        let data = try await send(table: "mos_human_tasks", filters: [
            .init(name: "source", value: "in.(grok-relay,dots-relay)"),
            .init(name: "status", value: "eq.open"),
            .init(name: "select", value: "id,title,body,resume_objective,created_at,source,resume_agent"),
            .init(name: "order", value: "created_at.asc"),
        ])
        return try MitamaNotificationClient(environment: environment)
            .decoder.decode([MitamaHumanTask].self, from: data)
    }

    private func send(table: String, filters: [URLQueryItem] = []) async throws -> Data {
        guard let url = environment.endpoint(table, queryItems: filters) else { throw ClientError.invalidRequest }
        var request = environment.authorized(URLRequest(url: url))
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        let (data, response) = try await transport(request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw ClientError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }
}
