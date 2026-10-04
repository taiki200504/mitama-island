import Foundation

/// Provider-native questions rendered through the island’s structured prompt.
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

public struct PaseoPermissionAction: Equatable, Codable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var behavior: String
    public var variant: String?
    public var intent: String?
}

public struct PaseoPermissionContext: Equatable, Codable, Sendable {
    public var agentID: String
    public var requestID: String
    public var provider: String
    public var kind: String
    public var currentModeID: String?
    public var currentModeLabel: String?
    public var actions: [PaseoPermissionAction]
}

public struct PaseoAgentBinding: Equatable, Sendable {
    public var agentID: String
    public var sessionID: String
    public var provider: String
    public var hostProvider: String
    public var title: String
    public var cwd: String
    public var currentModeID: String?
    public var currentModeLabel: String?
    public var parentAgentID: String? = nil
    public var jumpTarget: JumpTarget {
        JumpTarget(terminalApp: "Paseo", workspaceName: cwd, paneTitle: title,
                   workingDirectory: cwd, terminalSessionID: sessionID,
                   paseoAgentID: agentID, paseoServerID: PaseoServerIdentity.read())
    }
}

private enum PaseoProviderAliases {
    struct Configuration: Decodable {
        struct Providers: Decodable {
            struct Custom: Decodable { var extends: String }
            var custom: [String: Custom]?
        }
        var providers: Providers?
    }
    static let values: [String: String] = {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".paseo/config.json")
        guard let data = try? Data(contentsOf: url), let config = try? JSONDecoder().decode(Configuration.self, from: data) else { return [:] }
        return config.providers?.custom?.mapValues(\.extends) ?? [:]
    }()
    static func canonical(_ provider: String, aliases: [String: String]) -> String? {
        var value = provider
        var seen: Set<String> = []
        while let next = aliases[value] {
            guard seen.insert(value).inserted else { return nil }
            value = next
        }
        return ["claude", "codex", "opencode", "gemini", "acp"].contains(value) ? value : nil
    }
}

public enum PaseoServerIdentity {
    public static func read(url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".paseo/server-id")) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let id = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.count <= 128,
              id.rangeOfCharacter(from: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.").inverted) == nil else { return nil }
        return id
    }
}

public struct PaseoPendingRequest: Equatable, Sendable {
    public var binding: PaseoAgentBinding
    public var requestID: String
    public var name: String
    public var kind: String
    public var input: ClaudeHookJSONValue
    public var toolUseID: String?
    public var question: PaseoQuestion?
    public var permission: PermissionRequest?
    /// Keep the entire provider request for stale-request validation.
    public var originalRequest: ClaudeHookJSONValue
    public var sessionID: String { binding.sessionID }
    public var context: PaseoPermissionContext {
        permission?.paseoContext ?? PaseoPermissionContext(
            agentID: binding.agentID, requestID: requestID, provider: binding.provider, kind: kind,
            currentModeID: binding.currentModeID, currentModeLabel: binding.currentModeLabel, actions: [])
    }
}

@MainActor
public final class PaseoQuestionCoordinator {
    public typealias Call = @Sendable (String, ClaudeHookJSONValue) async throws -> ClaudeHookJSONValue
    private let call: Call
    private let providerAliases: [String: String]
    private var task: Task<Void, Never>?
    private var polling = false
    private var sending: Set<String> = []
    private var bindings: [String: PaseoAgentBinding] = [:]
    public private(set) var delegatedSessionIDs: Set<String> = []
    public var onDelegationChange: ((Set<String>) -> Void)?
    public private(set) var sessionsWithoutPending: Set<String> = []
    public private(set) var requests: [String: PaseoPendingRequest] = [:]
    public var questions: [String: PaseoQuestion] { requests.compactMapValues(\.question) }
    public var onChange: (([String: PaseoQuestion], [String: PaseoQuestion]) -> Void)?
    public var onRequestsChange: (([String: PaseoPendingRequest], [String: PaseoPendingRequest]) -> Void)?

    public init(call: @escaping Call = { name, input in try await PaseoMCPClient().call(name, arguments: input) }, providerAliases: [String: String]? = nil) {
        self.call = call
        self.providerAliases = providerAliases ?? PaseoProviderAliases.values
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
            guard let permissions = result.paseoObject?["permissions"]?.paseoArray else { throw PaseoQuestionError.invalidResponse }
            let agentIDs = Set(permissions.compactMap { value -> String? in
                guard let object = value.paseoObject, object["request"]?.paseoObject?["id"]?.paseoString != nil,
                      let id = object["agentId"]?.paseoString, !id.isEmpty else { return nil }
                return id
            })
            var found = requests.filter { sending.contains($0.value.binding.agentID) }
            var ambiguous: Set<String> = []
            for agentID in agentIDs.sorted() {
                try Task.checkCancellation()
                if sending.contains(agentID) { continue }
                let status = try await call("get_agent_status", .object(["agentId": .string(agentID)]))
                guard let snapshot = status.paseoObject?["snapshot"]?.paseoObject,
                      let binding = Self.binding(snapshot: snapshot, agentID: agentID, aliases: providerAliases) else { throw PaseoQuestionError.invalidResponse }
                await updateDelegation(binding)
                bindings[binding.sessionID] = binding
                if snapshot["pendingPermissions"]?.paseoArray?.isEmpty == true { sessionsWithoutPending.insert(binding.sessionID) }
                else { sessionsWithoutPending.remove(binding.sessionID) }
                // One actionable card per native session; subsequent SDK requests are picked up after resolution.
                guard var pending = Self.pending(snapshot: snapshot, binding: binding) else { continue }
                if ambiguous.contains(binding.sessionID) { continue }
                if let other = found[binding.sessionID], other.binding.agentID != agentID {
                    found.removeValue(forKey: binding.sessionID)
                    bindings.removeValue(forKey: binding.sessionID)
                    ambiguous.insert(binding.sessionID)
                    continue
                }
                if let old = requests[binding.sessionID], old.requestID == pending.requestID,
                   old.originalRequest == pending.originalRequest {
                    pending.question = old.question
                    if var permission = pending.permission, let oldID = old.permission?.id {
                        permission.id = oldID
                        pending.permission = permission
                    }
                }
                found[binding.sessionID] = pending
            }
            try Task.checkCancellation()
            let previous = requests
            requests = found
            if previous != found {
                onRequestsChange?(found, previous)
                onChange?(questions, previous.compactMapValues(\.question))
            }
        } catch { /* Daemon unavailable: retain actionable cards and retry quietly. */ }
    }

    /// Used only for an explicit jump lacking IDs, never as a polling scan.
    public func resolveBinding(sessionID: String) async throws -> PaseoAgentBinding {
        if let known = bindings[sessionID] { return known }
        let matches = try await reconcileBindings(sessionIDs: [sessionID])
        guard let match = matches[sessionID] else { throw PaseoQuestionError.expired }
        return match
    }

    public func reconcileBindings(sessionIDs: Set<String>) async throws -> [String: PaseoAgentBinding] {
        guard !sessionIDs.isEmpty else { return [:] }
        let result = try await call("list_agents", .object(["limit": .number(200), "sinceHours": .number(720)]))
        guard let agents = result.paseoObject?["agents"]?.paseoArray else { throw PaseoQuestionError.invalidResponse }
        var matches: [String: PaseoAgentBinding] = [:]
        var ambiguous: Set<String> = []
        for agent in agents {
            try Task.checkCancellation()
            guard let id = agent.paseoObject?["id"]?.paseoString else { continue }
            let status = try await call("get_agent_status", .object(["agentId": .string(id)]))
            guard let snapshot = status.paseoObject?["snapshot"]?.paseoObject,
                  let binding = Self.binding(snapshot: snapshot, agentID: id, aliases: providerAliases), sessionIDs.contains(binding.sessionID) else { continue }
            if matches[binding.sessionID] != nil { ambiguous.insert(binding.sessionID); continue }
            await updateDelegation(binding)
            matches[binding.sessionID] = binding
            if snapshot["pendingPermissions"]?.paseoArray?.isEmpty == true { sessionsWithoutPending.insert(binding.sessionID) }
            else { sessionsWithoutPending.remove(binding.sessionID) }
        }
        for id in ambiguous { matches.removeValue(forKey: id); sessionsWithoutPending.remove(id) }
        bindings.merge(matches) { _, current in current }
        return matches
    }

    /// A child remains actionable internally; its existing parent owns its permission workflow.
    private func updateDelegation(_ binding: PaseoAgentBinding) async {
        var delegated = false
        if let parentID = binding.parentAgentID, parentID != binding.agentID,
           let result = try? await call("get_agent_status", .object(["agentId": .string(parentID)])),
           let snapshot = result.paseoObject?["snapshot"]?.paseoObject {
            delegated = Self.parentCanHandle(snapshot: snapshot, parentID: parentID)
        }
        let previous = delegatedSessionIDs
        if delegated { delegatedSessionIDs.insert(binding.sessionID) }
        else { delegatedSessionIDs.remove(binding.sessionID) }
        if previous != delegatedSessionIDs { onDelegationChange?(delegatedSessionIDs) }
    }

    static func parentCanHandle(snapshot: [String: ClaudeHookJSONValue], parentID: String) -> Bool {
        guard snapshot["id"]?.paseoString == parentID,
              let status = snapshot["status"]?.paseoString,
              ["initializing", "idle", "running"].contains(status),
              snapshot["providerUnavailable"]?.paseoBool != true else { return false }
        if let archived = snapshot["archivedAt"], archived != .null { return false }
        return true
    }

    public func needsParentHandoff(sessionID: String) -> Bool {
        bindings[sessionID]?.parentAgentID != nil && !delegatedSessionIDs.contains(sessionID)
    }

    public func answer(sessionID: String, promptID: UUID, response: QuestionPromptResponse) async throws {
        guard let pending = requests[sessionID], let question = pending.question, question.prompt.id == promptID else { throw PaseoQuestionError.expired }
        var answers = response.answers
        if answers.isEmpty, question.prompt.questions.count == 1,
           let raw = response.rawAnswer, let item = question.prompt.questions.first { answers[item.responseKey] = raw }
        // Older callers keyed Codex answers by text. Convert only when text is unambiguous.
        if pending.binding.provider == "codex" {
            for item in question.prompt.questions where answers[item.responseKey] == nil {
                if question.prompt.questions.filter({ $0.question == item.question }).count == 1,
                   let value = answers.removeValue(forKey: item.question) { answers[item.responseKey] = value }
            }
        }
        let keys = Set(question.prompt.questions.map(\.responseKey))
        guard Set(answers.keys) == keys, answers.values.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw PaseoQuestionError.invalidAnswer
        }
        var input = pending.input.paseoObject ?? [:]
        if pending.binding.provider == "claude" {
            let payload = ClaudeHookPayload(cwd: question.cwd, hookEventName: .permissionRequest,
                                           sessionID: sessionID, toolName: "AskUserQuestion", toolInput: pending.input)
            let normalized = QuestionPromptResponse(answers: answers, annotations: response.annotations)
            input = BridgeServer.mergedClaudeQuestionInput(payload: payload, prompt: question.prompt, response: normalized).paseoObject ?? [:]
        } else { input["answers"] = .object(answers.mapValues { .string($0) }) }
        try await submit(pending, response: .object(["behavior": .string("allow"), "updatedInput": .object(input)]))
    }

    public func approve(sessionID: String, requestID: String, action: ApprovalAction) async throws -> PermissionResolution {
        guard let pending = requests[sessionID], pending.requestID == requestID,
              let permission = pending.permission else { throw PaseoQuestionError.expired }
        let context = pending.context
        guard !permission.requiresTerminalApproval else { throw PaseoQuestionError.invalidAnswer }
        var response: [String: ClaudeHookJSONValue] = [:]
        var resolution: PermissionResolution
        switch action {
        case .deny:
            response["behavior"] = .string("deny")
            resolution = .deny(message: "Paseoの要求を拒否しました。", interrupt: false)
            if !context.actions.isEmpty {
                guard let offered = context.actions.first(where: { $0.behavior == "deny" }) else { throw PaseoQuestionError.invalidAnswer }
                response["selectedActionId"] = .string(offered.id)
            }
        case .allowOnce:
            response["behavior"] = .string("allow")
            resolution = .allowOnce(updatedInput: pending.input)
            if !context.actions.isEmpty {
                let preservesBypass = pending.kind == "plan" && context.actions.contains { $0.intent == "implement_resume" }
                let offered = preservesBypass
                    ? context.actions.first(where: { $0.behavior == "allow" && $0.intent == "implement_resume" })
                        ?? context.actions.first(where: { $0.behavior == "allow" && $0.intent != "implement_resume" })
                    : context.actions.first(where: { $0.behavior == "allow" && $0.intent != "implement_resume" })
                guard let offered else { throw PaseoQuestionError.invalidAnswer }
                response["selectedActionId"] = .string(offered.id)
            }
        case let .paseoAction(requestID, id):
            guard requestID == pending.requestID, let offered = context.actions.first(where: { $0.id == id }), ["allow", "deny"].contains(offered.behavior) else { throw PaseoQuestionError.invalidAnswer }
            response["behavior"] = .string(offered.behavior)
            response["selectedActionId"] = .string(id)
            resolution = offered.behavior == "allow" ? .allowOnce(updatedInput: pending.input) : .deny(message: "Paseoの要求を拒否しました。", interrupt: false)
        case let .allowWithUpdates(updates):
            guard pending.binding.provider == "claude", pending.kind == "tool", !updates.isEmpty,
                  updates.allSatisfy({ permission.suggestedUpdates.contains($0) }) else { throw PaseoQuestionError.invalidAnswer }
            response["behavior"] = .string("allow")
            response["updatedPermissions"] = try JSONDecoder().decode(ClaudeHookJSONValue.self, from: JSONEncoder().encode(updates))
            resolution = .allowOnce(updatedInput: pending.input, updatedPermissions: updates)
        }
        if response["behavior"]?.paseoString == "allow" { response["updatedInput"] = pending.input }
        try await submit(pending, response: .object(response))
        return resolution
    }

    private func submit(_ pending: PaseoPendingRequest, response: ClaudeHookJSONValue) async throws {
        guard sending.insert(pending.binding.agentID).inserted else { throw PaseoQuestionError.sending }
        defer { sending.remove(pending.binding.agentID) }
        let status = try await call("get_agent_status", .object(["agentId": .string(pending.binding.agentID)]))
        guard let snapshot = status.paseoObject?["snapshot"]?.paseoObject,
              let binding = Self.binding(snapshot: snapshot, agentID: pending.binding.agentID, aliases: providerAliases), binding.sessionID == pending.sessionID,
              binding.provider == pending.binding.provider,
              let current = Self.pending(snapshot: snapshot, binding: binding, requestID: pending.requestID),
              current.originalRequest == pending.originalRequest else { throw PaseoQuestionError.expired }
        let result = try await call("respond_to_permission", .object([
            "agentId": .string(binding.agentID), "requestId": .string(pending.requestID), "response": response
        ]))
        guard result.paseoObject?["success"]?.paseoBool == true else { throw PaseoQuestionError.invalidResponse }
        if requests[pending.sessionID]?.requestID == pending.requestID { requests.removeValue(forKey: pending.sessionID) }
    }

    static func binding(snapshot: [String: ClaudeHookJSONValue], agentID: String, aliases: [String: String] = [:]) -> PaseoAgentBinding? {
        guard snapshot["id"]?.paseoString == agentID, let hostProvider = snapshot["provider"]?.paseoString,
              let provider = PaseoProviderAliases.canonical(hostProvider, aliases: aliases),
              let persistence = snapshot["persistence"]?.paseoObject,
              persistence["provider"]?.paseoString == nil || persistence["provider"]?.paseoString == hostProvider,
              let native = persistence["sessionId"]?.paseoString ?? persistence["nativeHandle"]?.paseoString, !native.isEmpty, !native.hasPrefix("{"), !native.hasPrefix("[") else { return nil }
        let mode = snapshot["currentModeId"]?.paseoString
        let label = snapshot["availableModes"]?.paseoArray?.first { $0.paseoObject?["id"]?.paseoString == mode }?.paseoObject?["label"]?.paseoString
        let rawParent = snapshot["labels"]?.paseoObject?["paseo.parent-agent-id"]?.paseoString?.trimmingCharacters(in: .whitespacesAndNewlines)
        return PaseoAgentBinding(agentID: agentID, sessionID: native, provider: provider, hostProvider: hostProvider,
                                 title: snapshot["title"]?.paseoString ?? "Paseo", cwd: snapshot["cwd"]?.paseoString ?? "",
                                 currentModeID: mode, currentModeLabel: label ?? mode,
                                 parentAgentID: rawParent?.isEmpty == false ? rawParent : nil)
    }

    static func pending(snapshot: [String: ClaudeHookJSONValue], binding: PaseoAgentBinding, requestID: String? = nil) -> PaseoPendingRequest? {
        for raw in snapshot["pendingPermissions"]?.paseoArray ?? [] {
            guard let object = raw.paseoObject, let id = object["id"]?.paseoString, !id.isEmpty,
                  requestID == nil || requestID == id,
                  object["provider"]?.paseoString == nil || object["provider"]?.paseoString == binding.provider,
                  let name = object["name"]?.paseoString else { continue }
            let kind = object["kind"]?.paseoString ?? (name == "AskUserQuestion" ? "question" : "tool")
            let input = object["input"] ?? .object([:])
            let toolID = object["metadata"]?.paseoObject?["toolUseId"]?.paseoString
            var pending = PaseoPendingRequest(binding: binding, requestID: id, name: name, kind: kind,
                                             input: input, toolUseID: toolID, question: nil, permission: nil, originalRequest: raw)
            if kind == "question" || name == "AskUserQuestion" {
                guard let prompt = questionPrompt(input: input, provider: binding.provider) else { continue }
                pending.question = PaseoQuestion(agentID: binding.agentID, requestID: id, sessionID: binding.sessionID,
                                                title: binding.title, cwd: binding.cwd, input: input, prompt: prompt)
            } else {
                let actions = (object["actions"]?.paseoArray ?? []).compactMap { raw -> PaseoPermissionAction? in
                    guard let value = raw.paseoObject, let id = value["id"]?.paseoString,
                          let label = value["label"]?.paseoString, let behavior = value["behavior"]?.paseoString,
                          ["allow", "deny"].contains(behavior) else { return nil }
                    return PaseoPermissionAction(id: id, label: label, behavior: behavior,
                                                 variant: value["variant"]?.paseoString, intent: value["intent"]?.paseoString)
                }
                let suggestions: [ClaudePermissionUpdate]
                if binding.provider == "claude", kind == "tool", let raw = object["suggestions"],
                   let data = try? JSONEncoder().encode(raw), let decoded = try? JSONDecoder().decode([ClaudePermissionUpdate].self, from: data) { suggestions = decoded }
                else { suggestions = [] }
                let summary = object["detail"]?.paseoObject?["command"]?.paseoString
                    ?? input.paseoObject?["command"]?.paseoString
                    ?? object["description"]?.paseoString
                    ?? object["metadata"]?.paseoObject?["planText"]?.paseoString
                    ?? input.paseoObject?["plan"]?.paseoString ?? name
                pending.permission = PermissionRequest(title: "実行の許可", summary: summary, affectedPath: binding.cwd,
                    primaryActionTitle: "今回だけ許可", secondaryActionTitle: "拒否", toolName: name, toolUseID: toolID,
                    suggestedUpdates: suggestions, requiresTerminalApproval: kind != "tool" && actions.isEmpty, paseoContext: PaseoPermissionContext(agentID: binding.agentID, requestID: id,
                        provider: binding.provider, kind: kind, currentModeID: binding.currentModeID,
                        currentModeLabel: binding.currentModeLabel, actions: actions))
            }
            return pending
        }
        return nil
    }

    private static func questionPrompt(input: ClaudeHookJSONValue, provider: String) -> QuestionPrompt? {
        guard let rawQuestions = input.paseoObject?["questions"]?.paseoArray, !rawQuestions.isEmpty else { return nil }
        var questions: [QuestionPromptItem] = []
        for (index, raw) in rawQuestions.enumerated() {
            guard let object = raw.paseoObject, let text = object["question"]?.paseoString, !text.isEmpty else { return nil }
            let header = object["header"]?.paseoString ?? "Question \(index + 1)"
            var options = (object["options"]?.paseoArray ?? []).compactMap { raw -> QuestionOption? in
                guard let option = raw.paseoObject, let label = option["label"]?.paseoString else { return nil }
                return QuestionOption(label: label, description: option["description"]?.paseoString ?? "")
            }
            options.append(QuestionOption(label: "その他（自由入力）", allowsFreeform: true))
            questions.append(QuestionPromptItem(question: text, header: header, options: options,
                multiSelect: object["multiSelect"]?.paseoBool ?? false, answerKey: provider == "codex" ? header : nil))
        }
        guard Set(questions.map(\.responseKey)).count == questions.count else { return nil }
        return QuestionPrompt(title: questions.count == 1 ? questions[0].question : "質問に回答してください", questions: questions)
    }
}

private extension ClaudeHookJSONValue {
    var paseoString: String? { if case let .string(value) = self { return value }; return nil }
    var paseoBool: Bool? { if case let .boolean(value) = self { return value }; return nil }
    var paseoObject: [String: ClaudeHookJSONValue]? { if case let .object(value) = self { return value }; return nil }
    var paseoArray: [ClaudeHookJSONValue]? { if case let .array(value) = self { return value }; return nil }
}
