import Foundation
import Testing
@testable import OpenIslandCore

struct BrowserAutomationActivityTests {
    @Test("Nil on missing/corrupt file")
    func nilOnCorruptData() {
        let data = "not json".data(using: .utf8)!
        let now = Date()
        #expect(BrowserAutomationActivity.parse(data, now: now) == nil)
    }

    @Test("Nil on empty data")
    func nilOnEmptyData() {
        let data = Data()
        let now = Date()
        #expect(BrowserAutomationActivity.parse(data, now: now) == nil)
    }

    @Test("Parses valid JSON with fresh timestamp")
    func parseFreshActivity() {
        let now = Date()
        let json = """
        {
            "accountId": "gugen",
            "accountLabel": "Gugen",
            "title": "GitHub Issues",
            "url": "https://github.com/issues",
            "at": "\(ISO8601DateFormatter().string(from: now))"
        }
        """
        let data = json.data(using: .utf8)!
        let activity = BrowserAutomationActivity.parse(data, now: now, freshness: 600)
        #expect(activity != nil)
        #expect(activity?.accountId == "gugen")
        #expect(activity?.title == "GitHub Issues")
    }

    @Test("Nil when timestamp is too old")
    func nilOnStaleTimestamp() {
        let now = Date()
        let staleTime = now.addingTimeInterval(-15 * 60) // 15 minutes ago
        let json = """
        {
            "accountId": "gugen",
            "accountLabel": "Gugen",
            "title": "GitHub Issues",
            "url": "https://github.com/issues",
            "at": "\(ISO8601DateFormatter().string(from: staleTime))"
        }
        """
        let data = json.data(using: .utf8)!
        let activity = BrowserAutomationActivity.parse(data, now: now, freshness: 600) // 10 min freshness
        #expect(activity == nil)
    }

    @Test("Accepts null URL")
    func nullUrl() {
        let now = Date()
        let json = """
        {
            "accountId": "gugen",
            "accountLabel": "Gugen",
            "title": "New Tab",
            "url": null,
            "at": "\(ISO8601DateFormatter().string(from: now))"
        }
        """
        let data = json.data(using: .utf8)!
        let activity = BrowserAutomationActivity.parse(data, now: now, freshness: 600)
        #expect(activity != nil)
        #expect(activity?.url == nil)
    }

    @Test("Boundary: exactly at freshness limit")
    func boundaryFreshness() {
        let now = Date()
        let boundaryTime = now.addingTimeInterval(-600) // Exactly 10 min ago
        let json = """
        {
            "accountId": "gugen",
            "accountLabel": "Gugen",
            "title": "Page",
            "url": null,
            "at": "\(ISO8601DateFormatter().string(from: boundaryTime))"
        }
        """
        let data = json.data(using: .utf8)!
        let activity = BrowserAutomationActivity.parse(data, now: now, freshness: 600)
        #expect(activity != nil)
    }

    @Test("Boundary: just past freshness limit")
    func boundaryExpired() {
        let now = Date()
        let expiredTime = now.addingTimeInterval(-601) // Just over 10 min
        let json = """
        {
            "accountId": "gugen",
            "accountLabel": "Gugen",
            "title": "Page",
            "url": null,
            "at": "\(ISO8601DateFormatter().string(from: expiredTime))"
        }
        """
        let data = json.data(using: .utf8)!
        let activity = BrowserAutomationActivity.parse(data, now: now, freshness: 600)
        #expect(activity == nil)
    }

    @Test("Nil when timestamp is in the future")
    func nilOnFutureTimestamp() {
        let now = Date()
        let futureTime = now.addingTimeInterval(60) // 1 minute in future
        let json = """
        {
            "accountId": "gugen",
            "accountLabel": "Gugen",
            "title": "Page",
            "url": null,
            "at": "\(ISO8601DateFormatter().string(from: futureTime))"
        }
        """
        let data = json.data(using: .utf8)!
        let activity = BrowserAutomationActivity.parse(data, now: now, freshness: 600)
        #expect(activity == nil)
    }
}
