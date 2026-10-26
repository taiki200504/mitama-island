import Foundation
import Testing
@testable import OpenIslandCore

struct WatchHTTPEndpointTests {
    @Test
    func invalidBodiesConsumeSharedBudgetAndRecoverAtWindowBoundary() {
        let endpoint = WatchHTTPEndpoint()
        let start = ContinuousClock.now
        let bodies: [String?] = [nil, "", "{", "{}", #"{"code":1}"#]
        for body in bodies {
            let status = endpoint.pairingResponse(body: body, now: start).status
            #expect(status == "400 Bad Request")
        }

        let blocked = endpoint.pairingResponse(body: validBody(endpoint), now: start.advanced(by: .seconds(119)))
        let blockedStatus = blocked.status
        let containsToken = blocked.body.contains("token")
        #expect(blockedStatus == "429 Too Many Requests")
        #expect(!containsToken)
        let recoveredStatus = endpoint.pairingResponse(body: validBody(endpoint), now: start.advanced(by: .seconds(120))).status
        #expect(recoveredStatus == "200 OK")
    }

    @Test
    func successAndCodeRotationDoNotResetBudget() {
        let endpoint = WatchHTTPEndpoint()
        let start = ContinuousClock.now
        for _ in 0..<5 {
            let status = endpoint.pairingResponse(body: validBody(endpoint), now: start).status
            #expect(status == "200 OK")
            endpoint.regeneratePairingCode()
            _ = endpoint.currentCode()
        }
        let validStatus = endpoint.pairingResponse(body: validBody(endpoint), now: start).status
        let invalidStatus = endpoint.pairingResponse(body: "{", now: start).status
        #expect(validStatus == "429 Too Many Requests")
        #expect(invalidStatus == "429 Too Many Requests")
    }

    @Test
    func attemptsExpireIndividuallyInsteadOfResettingTheWholeBudget() {
        let endpoint = WatchHTTPEndpoint()
        let start = ContinuousClock.now
        for seconds in 0..<5 {
            let status = endpoint.pairingResponse(body: nil, now: start.advanced(by: .seconds(seconds))).status
            #expect(status == "400 Bad Request")
        }
        let boundary = start.advanced(by: .seconds(120))
        let expiredAttemptStatus = endpoint.pairingResponse(body: nil, now: boundary).status
        let blockedStatus = endpoint.pairingResponse(body: validBody(endpoint), now: boundary).status
        #expect(expiredAttemptStatus == "400 Bad Request")
        #expect(blockedStatus == "429 Too Many Requests")
    }

    private func validBody(_ endpoint: WatchHTTPEndpoint) -> String {
        // Never log pairing codes or tokens, including assertion diagnostics.
        "{\"code\":\"\(endpoint.currentCode())\"}"
    }
}
