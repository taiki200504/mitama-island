import Foundation
import Testing
@testable import OpenIslandCore

struct RaphaelStatusTests {
    @Test("Parse valid status JSON")
    func parseValidStatus() throws {
        let json = """
        {"enabled":true,"running":true,"mic":false,"voice":false}
        """
        let data = try #require(json.data(using: .utf8))
        let status = RaphaelStatus.parse(from: data)

        #expect(status?.enabled == true)
        #expect(status?.running == true)
        #expect(status?.mic == false)
        #expect(status?.voice == false)
    }

    @Test("Parse status with all muted false")
    func parseStatusWithAllMutedFalse() throws {
        let json = """
        {"enabled":false,"running":false,"mic":true,"voice":true}
        """
        let data = try #require(json.data(using: .utf8))
        let status = RaphaelStatus.parse(from: data)

        #expect(status?.enabled == false)
        #expect(status?.running == false)
        #expect(status?.mic == true)
        #expect(status?.voice == true)
    }

    @Test("Invalid JSON returns nil")
    func invalidJsonReturnsNil() throws {
        let json = "not valid json"
        let data = try #require(json.data(using: .utf8))
        let status = RaphaelStatus.parse(from: data)

        #expect(status == nil)
    }

    @Test("Missing fields return nil")
    func missingFieldsReturnsNil() throws {
        let json = """
        {"enabled":true,"running":true}
        """
        let data = try #require(json.data(using: .utf8))
        let status = RaphaelStatus.parse(from: data)

        #expect(status == nil)
    }

    @Test("Equality works correctly")
    func equalityComparison() {
        let status1 = RaphaelStatus(enabled: true, running: true, mic: false, voice: false)
        let status2 = RaphaelStatus(enabled: true, running: true, mic: false, voice: false)
        let status3 = RaphaelStatus(enabled: false, running: true, mic: false, voice: false)

        #expect(status1 == status2)
        #expect(status1 != status3)
    }
}
