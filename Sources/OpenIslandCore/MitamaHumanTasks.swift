import Foundation

public struct MitamaHumanTask: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let body: String?
    public let resumeObjective: String?
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, body
        case resumeObjective = "resume_objective"
        case createdAt = "created_at"
    }
}

public enum MitamaHumanAnswer: String, Encodable, Sendable {
    case approve, reject
    public var label: String { self == .approve ? "実行する" : "却下" }
}

/// Only typed answers, relay jobs and decision records can be written through this client.
public struct MitamaHumanTaskClient: Sendable {
    public enum Result: Equatable, Sendable {
        case answered(jobID: String?, warning: String?)
        case alreadyAnswered
    }
    public enum ClientError: Error, LocalizedError {
        case invalidTask, requestFailed(Int), partial(String)
        public var errorDescription: String? {
            switch self {
            case .invalidTask: "依頼の形式が正しくありません"
            case .requestFailed(let status): "判断待ちの通信に失敗しました (HTTP \(status))"
            case .partial(let message): message
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
            .init(name: "source", value: "eq.grok-relay"),
            .init(name: "status", value: "eq.open"),
            .init(name: "select", value: "id,title,body,resume_objective,created_at"),
            .init(name: "order", value: "created_at.asc"),
        ])
        return try MitamaNotificationClient(environment: environment)
            .decoder.decode([MitamaHumanTask].self, from: data)
    }

    private struct Answer: Encodable {
        let status = "answered"
        let answer_key: MitamaHumanAnswer
        let answered_at: String
    }
    private struct RelayJob: Encodable {
        struct Input: Encodable { let objective: String; let human_task_id: String }
        let id: String
        let agent_id = "relay"
        let source = "hub"
        let status = "enqueued"
        let priority = 5
        let input: Input
    }
    private struct Resume: Encodable { let resume_job_id: String }
    private struct Decision: Encodable {
        let topic: String
        let decision: String
        let source = "island-decide"
    }
    private struct Row: Decodable { let id: String }

    public func answer(_ task: MitamaHumanTask, with answer: MitamaHumanAnswer, now: Date = .now) async throws -> Result {
        guard !task.id.isEmpty, task.id.count <= 200,
              task.id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_:")).contains($0) }),
              answer == .reject || !(task.resumeObjective ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientError.invalidTask
        }
        let filters: [URLQueryItem] = [.init(name: "id", value: "eq.\(task.id)"), .init(name: "source", value: "eq.grok-relay")]
        let data = try await send(table: "mos_human_tasks", method: "PATCH",
            filters: filters + [.init(name: "status", value: "eq.open"), .init(name: "select", value: "id")],
            body: JSONEncoder().encode(Answer(answer_key: answer, answered_at: ISO8601DateFormatter().string(from: now))), representation: true)
        let rows = try JSONDecoder().decode([Row].self, from: data)
        guard !rows.isEmpty else { return .alreadyAnswered }
        guard rows.count == 1, rows[0].id == task.id else { throw ClientError.invalidTask }

        var warning: String?
        do {
            _ = try await send(table: "mos_ceo_decisions", method: "POST",
                body: JSONEncoder().encode(Decision(topic: task.title, decision: answer.label)))
        } catch { warning = "回答は保存済みですが、決定の記録に失敗しました" }
        guard answer == .approve else { return .answered(jobID: nil, warning: warning) }
        let jobID = "island-decide-\(Int(now.timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8).lowercased())"
        do {
            _ = try await send(table: "mos_job_queue", method: "POST", body: JSONEncoder().encode(RelayJob(
                id: jobID, input: .init(objective: task.resumeObjective! + "\n\n本人の決定: 実行する", human_task_id: task.id))))
        } catch { throw ClientError.partial("回答は保存済みですが、実行ジョブを積めませんでした。Hubで確認してください") }
        do {
            _ = try await send(table: "mos_human_tasks", method: "PATCH", filters: filters,
                body: JSONEncoder().encode(Resume(resume_job_id: jobID)))
        } catch { warning = "実行ジョブは登録済みですが、依頼との紐付けに失敗しました。Hubで確認してください" }
        return .answered(jobID: jobID, warning: warning)
    }

    private func send(table: String, method: String = "GET", filters: [URLQueryItem] = [], body: Data? = nil, representation: Bool = false) async throws -> Data {
        guard method != "PATCH" || !filters.isEmpty,
              let url = environment.endpoint(table, queryItems: filters) else { throw ClientError.invalidTask }
        var request = environment.authorized(URLRequest(url: url))
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 30
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if representation { request.setValue("return=representation", forHTTPHeaderField: "Prefer") }
        let (data, response) = try await transport(request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw ClientError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }
}
