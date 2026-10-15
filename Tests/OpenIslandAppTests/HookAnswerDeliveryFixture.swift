import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// Holds delivery open so tests can check that state only changes after the ack.
@MainActor
final class HookAnswerDeliveryFixture {
    private(set) var commands: [BridgeCommand] = []
    private var replies: [CheckedContinuation<BridgeResponse, Never>] = []

    func send(_ command: BridgeCommand) async -> BridgeResponse {
        commands.append(command)
        return await withCheckedContinuation { replies.append($0) }
    }

    func waitForCommands(_ count: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while commands.count < count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(commands.count == count)
    }

    func reply(_ response: BridgeResponse = .acknowledged) {
        let pending = replies
        replies.removeAll()
        for continuation in pending { continuation.resume(returning: response) }
    }

    func waitForCompletion(_ model: AppModel) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !model.paseoSendingSessionIDs.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(model.paseoSendingSessionIDs.isEmpty)
    }
}
