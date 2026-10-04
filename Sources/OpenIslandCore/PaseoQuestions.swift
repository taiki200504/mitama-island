import Foundation

/// Only user questions are actionable here; tool approvals remain in Paseo.
public struct PaseoQuestion: Equatable, Sendable {
    public var agentID: String
    public var requestID: String
    public var sessionID: String
    public var title: String
    public var cwd: String
    public var input: ClaudeHookJSONValue
    public var prompt: QuestionPrompt
}

public enum PaseoQuestionError: Error { case invalidResponse, invalidAnswer, expired, sending }

public struct PaseoMCPClient: Sendable {
    public var endpoint: URL
    public init(endpoint: URL = URL(string: "http://127.0.0.1:6767/mcp/agents")!) {
        self.endpoint = endpoint
    }

    public func call(_ name: String, arguments: ClaudeHookJSONValue) async throws -> ClaudeHookJSONValue {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = name == "respond_to_permission" ? 10 : 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        let id = UUID().uuidString
        request.httpBody = try JSONEncoder().encode(ClaudeHookJSONValue.object([
            "jsonrpc": .string("2.0"), "id": .string(id), "method": .string("tools/call"),
            "params": .object(["name": .string(name), "arguments": arguments])
        ]))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = request.timeoutInterval
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PaseoQuestionError.invalidResponse }
        return try Self.decode(data, id: id)
    }

    public static func decode(_ data: Data, id: String? = nil) throws -> ClaudeHookJSONValue {
        let decoder = JSONDecoder()
        var envelopes: [ClaudeHookJSONValue] = []
        if let value = try? decoder.decode(ClaudeHookJSONValue.self, from: data) { envelopes.append(value) }
        else if let text = String(data: data, encoding: .utf8) {
            // SSE can contain unrelated notifications and multiple data lines.
            for event in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n") {
                let payload = event.components(separatedBy: "\n").filter { $0.hasPrefix("data:") }
                    .map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
                if let value = try? decoder.decode(ClaudeHookJSONValue.self, from: Data(payload.utf8)) { envelopes.append(value) }
            }
        }
        for envelope in envelopes {
            guard let object = envelope.paseoObject, id == nil || object["id"]?.paseoString == id else { continue }
            guard object["error"] == nil, let result = object["result"]?.paseoObject,
                  result["isError"]?.paseoBool != true else { throw PaseoQuestionError.invalidResponse }
            if let structured = result["structuredContent"] { return structured }
            for block in result["content"]?.paseoArray ?? [] {
                if let text = block.paseoObject?["text"]?.paseoString,
                   let value = try? decoder.decode(ClaudeHookJSONValue.self, from: Data(text.utf8)) { return value }
            }
            throw PaseoQuestionError.invalidResponse
        }
        throw PaseoQuestionError.invalidResponse
    }
}

@MainActor
public final class PaseoQuestionCoordinator {
    public typealias Call = @Sendable (String, ClaudeHookJSONValue) async throws -> ClaudeHookJSONValue
    private let call: Call
    private var task: Task<Void, Never>?
    private var polling = false
    private var sending: Set<String> = []
    public private(set) var questions: [String: PaseoQuestion] = [:]
    public var onChange: (([String: PaseoQuestion], [String: PaseoQuestion]) -> Void)?

    public init(call: @escaping Call = { name, input in try await PaseoMCPClient().call(name, arguments: input) }) {
        self.call = call
    }
    deinit { task?.cancel() }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }
    public func stop() { task?.cancel(); task = nil }

    public func poll() async {
        guard !polling else { return }
        polling = true
        defer { polling = false }
        do {
            let result = try await call("list_pending_permissions", .object([:]))
            guard let permissions = result.paseoObject?["permissions"]?.paseoArray else {
                throw PaseoQuestionError.invalidResponse
            }
            // Fetch native session identity only for agents actually waiting on a question.
            let agentIDs = Set(permissions.compactMap { permission -> String? in
                guard let object = permission.paseoObject,
                      object["request"]?.paseoObject?["name"]?.paseoString == "AskUserQuestion",
                      let id = object["agentId"]?.paseoString, !id.isEmpty else { return nil }
                return id
            })
            var found = questions.filter { sending.contains($0.value.agentID) }
            var ambiguousSessions: Set<String> = []
            for agentID in agentIDs.sorted() {
                try Task.checkCancellation()
                if sending.contains(agentID) { continue }
                let status = try await call("get_agent_status", .object(["agentId": .string(agentID)]))
                guard let snapshot = status.paseoObject?["snapshot"]?.paseoObject else {
                    throw PaseoQuestionError.invalidResponse
                }
                if let question = Self.question(snapshot: snapshot, agentID: agentID) {
                    if ambiguousSessions.contains(question.sessionID) { continue }
                    if let other = found[question.sessionID], other.agentID != question.agentID {
                        found.removeValue(forKey: question.sessionID)
                        ambiguousSessions.insert(question.sessionID)
                        continue
                    }
                    var stable = question
                    if let previous = questions[question.sessionID], previous.requestID == question.requestID,
                       previous.input == question.input { stable.prompt = previous.prompt }
                    found[question.sessionID] = stable
                }
            }
            try Task.checkCancellation()
            let previous = questions
            questions = found
            if previous != found { onChange?(found, previous) }
        } catch { /* Daemon unavailable: preserve existing hooks and retry quietly. */ }
    }

    public func answer(sessionID: String, promptID: UUID, response: QuestionPromptResponse) async throws {
        guard let question = questions[sessionID], question.prompt.id == promptID else { throw PaseoQuestionError.expired }
        var answers = response.answers
        if answers.isEmpty, question.prompt.questions.count == 1,
           let raw = response.rawAnswer, let text = question.prompt.questions.first?.question { answers[text] = raw }
        let requested = Set(question.prompt.questions.map(\.question))
        guard Set(answers.keys) == requested,
              answers.values.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw PaseoQuestionError.invalidAnswer
        }
        guard sending.insert(question.agentID).inserted else { throw PaseoQuestionError.sending }
        defer { sending.remove(question.agentID) }
        let status = try await call("get_agent_status", .object(["agentId": .string(question.agentID)]))
        guard let snapshot = status.paseoObject?["snapshot"]?.paseoObject,
              let current = Self.question(snapshot: snapshot, agentID: question.agentID),
              current.requestID == question.requestID, current.sessionID == sessionID,
              current.input == question.input else { throw PaseoQuestionError.expired }
        let payload = ClaudeHookPayload(cwd: question.cwd, hookEventName: .permissionRequest,
                                       sessionID: sessionID, toolName: "AskUserQuestion", toolInput: question.input)
        let updatedInput = BridgeServer.mergedClaudeQuestionInput(payload: payload, prompt: question.prompt, response: response)
        let result = try await call("respond_to_permission", .object([
            "agentId": .string(question.agentID), "requestId": .string(question.requestID),
            "response": .object(["behavior": .string("allow"), "updatedInput": updatedInput])
        ]))
        guard result.paseoObject?["success"]?.paseoBool == true,
              result.paseoObject?["error"] == nil,
              result.paseoObject?["status"]?.paseoString != "error" else { throw PaseoQuestionError.invalidResponse }
        if questions[sessionID]?.requestID == question.requestID { questions.removeValue(forKey: sessionID) }
    }

    static func question(snapshot: [String: ClaudeHookJSONValue], agentID: String) -> PaseoQuestion? {
        guard snapshot["id"]?.paseoString == agentID,
              let persistence = snapshot["persistence"]?.paseoObject,
              let sessionID = persistence["sessionId"]?.paseoString ?? persistence["nativeHandle"]?.paseoString,
              !sessionID.isEmpty else { return nil }
        for permission in snapshot["pendingPermissions"]?.paseoArray ?? [] {
            guard let object = permission.paseoObject, object["name"]?.paseoString == "AskUserQuestion",
                  let requestID = object["id"]?.paseoString, !requestID.isEmpty, let input = object["input"] else { continue }
            let cwd = snapshot["cwd"]?.paseoString ?? ""
            let payload = ClaudeHookPayload(cwd: cwd, hookEventName: .permissionRequest, sessionID: sessionID,
                                           toolName: "AskUserQuestion", toolInput: input)
            guard let prompt = payload.questionPrompt,
                  Set(prompt.questions.map(\.question)).count == prompt.questions.count else { continue }
            return PaseoQuestion(agentID: agentID, requestID: requestID, sessionID: sessionID,
                                 title: snapshot["title"]?.paseoString ?? "Paseo", cwd: cwd, input: input, prompt: prompt)
        }
        return nil
    }
}

private extension ClaudeHookJSONValue {
    var paseoString: String? { if case let .string(value) = self { return value }; return nil }
    var paseoBool: Bool? { if case let .boolean(value) = self { return value }; return nil }
    var paseoObject: [String: ClaudeHookJSONValue]? { if case let .object(value) = self { return value }; return nil }
    var paseoArray: [ClaudeHookJSONValue]? { if case let .array(value) = self { return value }; return nil }
}
