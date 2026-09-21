import Foundation
import Testing
@testable import OpenIslandCore

/// 島から mitama に手を出せる行為。ここで守っているのは「何を起こせないか」。
struct MitamaIslandActionTests {
    private let now = Date(timeIntervalSince1970: 1_758_000_000)

    // MARK: - 止めることしかできない

    /// 定期実行の行は消さず、止めた理由を必ず残す。理由の無い停止は、
    /// 3日後に自己改善が「障害」と誤診して勝手に戻す側の状態に戻る。
    @Test
    func stoppingAScheduleWritesTheReasonAndNeverEnablesIt() {
        let body = MitamaIslandAction
            .stopSchedule(id: "jobhunt-daily", reason: "本人希望で停止")
            .body(now: now)

        #expect(body["enabled"] as? Bool == false)
        #expect(body["off_reason"] as? String == "本人希望で停止")
        #expect(body["off_at"] as? String != nil)
    }

    @Test
    func aScheduleStopWithoutAReasonIsNotSent() {
        #expect(MitamaIslandAction.stopSchedule(id: "jobhunt-daily", reason: "   ").isValid == false)
        #expect(MitamaIslandAction.stopSchedule(id: "", reason: "理由").isValid == false)
        #expect(MitamaIslandAction.stopSchedule(id: "jobhunt-daily", reason: "理由").isValid)
    }

    // MARK: - 更新は必ず1行に当てる

    /// 絞り込みの無い PATCH は表を丸ごと書き換える。既存の行を直す行為は
    /// 例外なく主キーの条件を持つ。
    @Test
    func everyUpdateNarrowsToASingleRow() {
        let updates: [MitamaIslandAction] = [
            .stopSchedule(id: "jobhunt-daily", reason: "理由"),
            .replyToProposal(runDate: "2026-09-21", reply: .act),
        ]

        for action in updates {
            #expect(action.method == "PATCH")
            #expect(action.filters.count == 1)
            #expect(action.filters.first?.value?.hasPrefix("eq.") == true)
        }
    }

    @Test
    func aProposalReplyOnlyAcceptsARunDate() {
        #expect(MitamaIslandAction.replyToProposal(runDate: "2026-09-21", reply: .drop).isValid)
        #expect(MitamaIslandAction.replyToProposal(runDate: "2026-9-1", reply: .drop).isValid == false)
        #expect(MitamaIslandAction.replyToProposal(runDate: "", reply: .drop).isValid == false)
        #expect(MitamaIslandAction.replyToProposal(runDate: "gte.2026-01-01", reply: .drop).isValid == false)
    }

    /// 返事は2値だけ。「保留」を足すと督促が止まらない元の状態に戻る。
    @Test
    func aProposalReplyIsOnlyDoOrDrop() {
        #expect(MitamaProposalReply.allCases.map(\.rawValue).sorted() == ["do", "drop"])
    }

    // MARK: - メモ

    /// `source` は 'mobile|cli|ai_chat|slack|import|book' に縛られていて island が
    /// 無い。列を増やさずに出所を残すので、ここが崩れると挿入ごと弾かれる。
    @Test
    func aNoteUsesAnAcceptedSourceAndKeepsItsOrigin() {
        let body = MitamaIslandAction.note(" 思い付き ").body(now: now)

        #expect(body["body"] as? String == "思い付き")
        #expect(["mobile", "cli", "ai_chat", "slack", "import", "book"].contains(body["source"] as? String ?? ""))
        #expect(body["source_ref"] as? String == "island")
        #expect(body["tags"] as? [String] == ["island"])
    }

    @Test
    func anEmptyOrOversizedNoteIsNotSent() {
        #expect(MitamaIslandAction.note("  \n ").isValid == false)
        #expect(MitamaIslandAction.note(String(repeating: "あ", count: MitamaIslandAction.noteLimit + 1)).isValid == false)
        #expect(MitamaIslandAction.note("一行").isValid)
    }

    // MARK: - 運ぶところ

    @Test
    func anInvalidActionNeverReachesTheNetwork() async {
        let recorder = RequestRecorder()
        let client = MitamaWorkLogClient(
            environment: MitamaEnvironment(url: URL(string: "https://example.test")!, apiKey: "k"),
            session: recorder.session
        )

        let sent = await client.perform(.stopSchedule(id: "jobhunt-daily", reason: ""), now: now)

        #expect(sent == false)
        #expect(await recorder.requests.isEmpty)
    }

    @Test
    func aStopIsSentAsAPatchAgainstItsOwnRow() async {
        let recorder = RequestRecorder()
        let client = MitamaWorkLogClient(
            environment: MitamaEnvironment(url: URL(string: "https://example.test")!, apiKey: "k"),
            session: recorder.session
        )

        let sent = await client.perform(.stopSchedule(id: "jobhunt-daily", reason: "本人希望"), now: now)
        let requests = await recorder.requests

        #expect(sent)
        #expect(requests.count == 1)
        #expect(requests.first?.method == "PATCH")
        #expect(requests.first?.url.absoluteString == "https://example.test/rest/v1/mos_schedules?id=eq.jobhunt-daily")
        // 更新は単体、追加は配列。ここを取り違えると PostgREST が黙って 400 を返す。
        #expect(requests.first?.json?["enabled"] as? Bool == false)
    }
}

// MARK: - テスト用の口

/// 送ったものを覚えておくだけの URLSession。ネットワークには出ない。
private actor RequestRecorder {
    struct Sent: Sendable {
        let method: String
        let url: URL
        let bodyData: Data?

        var json: [String: Any]? {
            guard let bodyData else { return nil }
            return try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        }
    }

    private static let box = Box()

    nonisolated var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingProtocol.self]
        return URLSession(configuration: configuration)
    }

    var requests: [Sent] { Self.box.drainCopy() }

    init() { Self.box.reset() }

    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var sent: [Sent] = []

        func append(_ item: Sent) {
            lock.lock()
            defer { lock.unlock() }
            sent.append(item)
        }

        func drainCopy() -> [Sent] {
            lock.lock()
            defer { lock.unlock() }
            return sent
        }

        func reset() {
            lock.lock()
            defer { lock.unlock() }
            sent = []
        }
    }

    final class RecordingProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let body = request.httpBody ?? request.httpBodyStream.map { stream in
                stream.open()
                defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let read = stream.read(&buffer, maxLength: buffer.count)
                    guard read > 0 else { break }
                    data.append(contentsOf: buffer[0..<read])
                }
                return data
            }

            RequestRecorder.box.append(
                .init(method: request.httpMethod ?? "", url: request.url!, bodyData: body)
            )

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 204,
                httpVersion: nil,
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }
}
