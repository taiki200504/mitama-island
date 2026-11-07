import Foundation
import Testing
@testable import OpenIslandCore

/// The island holds a service key and no owner login. It may read what is waiting; it must never answer a decision
/// (v305: answers go through `mos_human_answer` with the owner's JWT — Hub, or the signed-in Mac app).
struct MitamaHumanTasksTests {
    actor Mock {
        var requests: [URLRequest] = []
        func send(_ request: URLRequest) -> (Data, URLResponse) {
            requests.append(request)
            return (Data("[]".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }
    private var environment: MitamaEnvironment { .init(url: URL(string: "https://example.supabase.co")!, apiKey: "test-key") }

    private func sourceText(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../Sources").standardized
        return try String(contentsOf: root.appending(path: relative), encoding: .utf8)
    }

    @Test func listingWhatIsWaitingIsAReadOnlyGet() async throws {
        let mock = Mock()
        let client = MitamaHumanTaskClient(environment: environment, transport: { await mock.send($0) })
        _ = try await client.fetchOpen()
        let requests = await mock.requests
        #expect(requests.count == 1)
        #expect(requests[0].httpMethod == "GET")
        #expect(requests[0].url?.lastPathComponent == "mos_human_tasks")
    }

    @Test func aTaskStillDecodesWithItsOrigin() throws {
        let data = Data(#"{"id":"t","title":"依頼","body":"全文","resume_objective":"作業する","created_at":"2026-10-12T00:00:00Z","source":"dots-relay"}"#.utf8)
        let task = try MitamaNotificationClient(environment: environment).decoder.decode(MitamaHumanTask.self, from: data)
        #expect(task.originLabel == "Dots")
    }

    @Test(arguments: ["OpenIslandCore/MitamaHumanTasks.swift", "OpenIslandApp/MitamaFeedCoordinator.swift", "OpenIslandApp/Views/Island/IslandSessionListView.swift"])
    func noPathLetsTheIslandWriteADecisionOrQueueAJob(file: String) throws {
        let text = try sourceText(file)
        #expect(!text.contains("\"PATCH\""), "\(file)")
        #expect(!text.contains("mos_ceo_decisions"), "\(file)")
        #expect(!text.contains("mos_job_queue"), "\(file)")
        #expect(!text.contains("island-decide"), "\(file)")
        #expect(!text.contains("MitamaHumanAnswer"), "\(file)")
        #expect(!text.contains("feed.answer"), "\(file)")
    }

    @Test func theIslandOnlyOpensTheHubToAnswer() throws {
        let view = try sourceText("OpenIslandApp/Views/Island/IslandSessionListView.swift")
        #expect(view.contains("Hubで答える"))
        #expect(view.contains("openMitamaHub(path: \"/decide\")"))
    }
}
