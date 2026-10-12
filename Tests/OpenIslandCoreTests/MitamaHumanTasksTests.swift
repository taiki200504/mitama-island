import Foundation
import Testing
@testable import OpenIslandCore

struct MitamaHumanTasksTests {
    actor Mock {
        let cas: String
        var requests: [URLRequest] = []
        init(cas: String) { self.cas = cas }
        func send(_ request: URLRequest) -> (Data, URLResponse) {
            requests.append(request)
            let isCAS = request.value(forHTTPHeaderField: "Prefer") == "return=representation"
            return (Data((isCAS ? cas : "").utf8), HTTPURLResponse(url: request.url!, statusCode: isCAS ? 200 : 204, httpVersion: nil, headerFields: nil)!)
        }
    }
    private let id = "e546785d-4b72-45a0-819c-a5f160180501"
    private var environment: MitamaEnvironment {
        .init(url: URL(string: "https://example.supabase.co")!, apiKey: "test-key")
    }
    private func task(source: String? = nil) throws -> MitamaHumanTask {
        let sourceField = source.map { ",\"source\":\"\($0)\"" } ?? ""
        let data = Data("""
        {"id":"\(id)","title":"依頼","body":"全文","resume_objective":"作業する","created_at":"2026-10-12T00:00:00Z"\(sourceField)}
        """.utf8)
        return try MitamaNotificationClient(environment: environment).decoder.decode(MitamaHumanTask.self, from: data)
    }

    @Test func casZeroDoesNotWriteAnythingElse() async throws {
        let mock = Mock(cas: "[]")
        let client = MitamaHumanTaskClient(environment: environment, transport: { await mock.send($0) })
        #expect(try await client.answer(task(), with: .approve) == .alreadyAnswered)
        let requests = await mock.requests
        #expect(requests.count == 1)
        #expect(requests[0].httpMethod == "PATCH")
        let query = URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(query.contains(.init(name: "status", value: "eq.open")))
        #expect(query.contains(.init(name: "id", value: "eq.\(id)")))
    }

    @Test func rejectRecordsDecisionWithoutEnqueue() async throws {
        let mock = Mock(cas: "[{\"id\":\"\(id)\"}]")
        let client = MitamaHumanTaskClient(environment: environment, transport: { await mock.send($0) })
        #expect(try await client.answer(task(), with: .reject) == .answered(jobID: nil, warning: nil))
        let requests = await mock.requests
        #expect(requests.count == 2)
        #expect(!requests.contains { $0.url!.lastPathComponent == "mos_job_queue" })
        let decision = try JSONSerialization.jsonObject(with: requests[1].httpBody!) as! [String: String]
        #expect(decision == ["topic": "依頼", "decision": "却下", "source": "island-decide"])
    }

    @Test func approveEnqueuesExactlyOneRelayJobAndLinksIt() async throws {
        let mock = Mock(cas: "[{\"id\":\"\(id)\"}]")
        let client = MitamaHumanTaskClient(environment: environment, transport: { await mock.send($0) })
        let result = try await client.answer(task(), with: .approve, now: Date(timeIntervalSince1970: 1000))
        guard case .answered(let jobID, nil) = result else { Issue.record("回答が完了しませんでした"); return }
        let requests = await mock.requests
        let jobs = requests.filter { $0.url!.lastPathComponent == "mos_job_queue" }
        #expect(jobs.count == 1)
        let job = try JSONSerialization.jsonObject(with: jobs[0].httpBody!) as! [String: Any]
        #expect(job["id"] as? String == jobID)
        #expect(jobID?.hasPrefix("island-decide-1000000-") == true)
        #expect(job["agent_id"] as? String == "relay")
        #expect(job["source"] as? String == "hub")
        #expect(job["status"] as? String == "enqueued")
        #expect(job["priority"] as? Int == 5)
        let input = job["input"] as! [String: String]
        #expect(input == ["objective": "作業する\n\n本人の決定: 実行する", "human_task_id": id])
        let resume = try JSONSerialization.jsonObject(with: requests.last!.httpBody!) as! [String: String]
        #expect(resume["resume_job_id"] == jobID)
        #expect(requests.count == 4)
    }

    @Test func dotsTaskIsAnsweredOnItsOwnSourceAndTagged() async throws {
        let mock = Mock(cas: "[{\"id\":\"\(id)\"}]")
        let client = MitamaHumanTaskClient(environment: environment, transport: { await mock.send($0) })
        let dots = try task(source: "dots-relay")
        #expect(dots.originLabel == "Dots")
        _ = try await client.answer(dots, with: .approve, now: Date(timeIntervalSince1970: 1000))
        let requests = await mock.requests
        #expect(requests.first!.url!.query!.contains("source=eq.dots-relay"))
        let job = try JSONSerialization.jsonObject(with: requests.first { $0.url!.lastPathComponent == "mos_job_queue" }!.httpBody!) as! [String: Any]
        #expect((job["input"] as! [String: Any])["relay_source"] as? String == "dots-relay")
    }
}
