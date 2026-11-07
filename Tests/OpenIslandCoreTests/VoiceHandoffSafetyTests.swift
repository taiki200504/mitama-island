import Foundation
import Testing
@testable import OpenIslandCore

/// P3① — one utterance keeps one id and one thread until its receipt is confirmed, however many times it is sent again.
struct PendingHandoffStoreTests {
    private func store() -> PendingHandoffStore { PendingHandoffStore(defaults: UserDefaults(suiteName: UUID().uuidString)!) }
    private let id = "6f1c2d3e-4a5b-4c6d-8e7f-0a1b2c3d4e5f"

    @Test
    func theSameUtteranceKeepsItsThreadAcrossRetries() throws {
        let s = store()
        let first = try #require(s.begin(utteranceID: id, text: "朝の準備"))
        let again = try #require(s.begin(utteranceID: id, text: "朝の準備"))
        #expect(again.utteranceID == first.utteranceID)
        #expect(again.thread == first.thread)
        #expect(VoiceHandoff.isUUIDv4(first.thread))
    }

    @Test
    func aRestartKeepsItToo() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let first = try #require(PendingHandoffStore(defaults: defaults).begin(utteranceID: id, text: "朝の準備"))
        let after = try #require(PendingHandoffStore(defaults: defaults).begin(utteranceID: id, text: "朝の準備"))
        #expect(after.thread == first.thread)
    }

    @Test
    func theSameIDWithOtherTextIsRefusedNotGivenANewID() {
        let s = store()
        _ = s.begin(utteranceID: id, text: "朝の準備")
        #expect(s.begin(utteranceID: id, text: "別の文") == nil)
    }

    @Test
    func aDifferentUtteranceIsANewThread() throws {
        let s = store()
        let a = try #require(s.begin(utteranceID: id, text: "x"))
        let b = try #require(s.begin(utteranceID: "0a1b2c3d-4e5f-4a6b-9c7d-8e9f0a1b2c3d", text: "y"))
        #expect(a.thread != b.thread)
        #expect(s.all().count == 2)
    }

    @Test
    func aConfirmedReceiptClearsItAndAnIdThatIsNotAUUIDv4IsRefused() {
        let s = store()
        _ = s.begin(utteranceID: id, text: "x")
        s.acknowledge(utteranceID: id)
        #expect(s.all().isEmpty)
        #expect(s.begin(utteranceID: "u1", text: "x") == nil)
        #expect(s.begin(utteranceID: id, text: " ") == nil)
    }

    @Test
    func thePlanUsesTheGivenIDsAndNeverMintsNewOnes() throws {
        let pending = try #require(store().begin(utteranceID: id, text: "朝の準備"))
        guard case .mac(let url) = VoiceHandoff.plan(pending, macAppVerified: true) else { Issue.record("mac"); return }
        guard case .mac(let again) = VoiceHandoff.plan(pending, macAppVerified: true) else { Issue.record("mac"); return }
        #expect(url == again)
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["utterance"] == id)
        #expect(items["thread"] == pending.thread)
    }
}

/// P3② — a link is opened only in an app whose bundle id AND signature were checked; anything else falls to the Hub.
struct RecipientAppCheckTests {
    private let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")

    @Test
    func aPinnedRequirementOnTheRightAppPasses() {
        let req = #"anchor apple and identifier "com.apple.calculator""#
        #expect(RecipientAppCheck.verified(calculator, bundleID: "com.apple.calculator", requirement: req) == calculator)
    }

    @Test
    func aWrongIdentifierOrBundleIDFails() {
        #expect(RecipientAppCheck.verified(calculator, bundleID: "com.apple.calculator", requirement: #"anchor apple and identifier "app.mitama.os.mac""#) == nil)
        #expect(RecipientAppCheck.verified(calculator, bundleID: "app.mitama.os.mac", requirement: #"anchor apple and identifier "com.apple.calculator""#) == nil)
    }

    @Test
    func aRequirementThatDoesNotPinTheSignerIsRefusedEvenIfItMatches() {
        #expect(RecipientAppCheck.verified(calculator, bundleID: "com.apple.calculator", requirement: #"identifier "com.apple.calculator""#) == nil)
        #expect(RecipientAppCheck.verified(calculator, bundleID: "com.apple.calculator", requirement: "") == nil)
        #expect(RecipientAppCheck.verified(calculator, bundleID: "com.apple.calculator", requirement: nil) == nil)
    }

    @Test
    func noCandidateOrAMissingPathFails() {
        let req = #"anchor apple and identifier "com.apple.calculator""#
        #expect(RecipientAppCheck.verified(nil, bundleID: "com.apple.calculator", requirement: req) == nil)
        #expect(RecipientAppCheck.verified(URL(fileURLWithPath: "/nonexistent/Nope.app"), bundleID: "com.apple.calculator", requirement: req) == nil)
    }

    @Test
    func anUnsignedLookAlikeWithTheSameBundleIDFails() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("Fake.app/Contents")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "app.mitama.os.mac", "CFBundleExecutable": "fake", "CFBundleName": "Fake"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: dir.appendingPathComponent("Info.plist"))
        let app = dir.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let req = #"anchor apple generic and identifier "app.mitama.os.mac" and certificate leaf = H"0ef85627c63304d83ebc3366c195948b7db19721""#
        #expect(RecipientAppCheck.verified(app, bundleID: "app.mitama.os.mac", requirement: req) == nil)
    }
}

/// T-N, the island's side — the island rings a meeting-start alert only when the one place in the database says it is
/// the owner. If that cannot be read, it does not ring (a missed alert beats a doubled one).
struct MeetingRingerTests {
    private func rows(_ json: String) -> MeetingAlertOwner? { MeetingRinger.owner(fromRows: Data(json.utf8)) }

    @Test
    func theValueInTheRowIsTheOwner() {
        #expect(rows(#"[{"meeting_ringer":"island"}]"#) == .island)
        #expect(rows(#"[{"meeting_ringer":"mac"}]"#) == .mac)
        #expect(rows(#"[{"meeting_ringer":"iphone"}]"#) == .iphone)
    }

    @Test
    func noRowYetMeansTheIslandKeepsItLikeTheDatabaseDefault() {
        #expect(rows("[]") == .island)
    }

    @Test
    func anythingUnreadableIsNil() {
        #expect(rows(#"[{"meeting_ringer":"tablet"}]"#) == nil)
        #expect(rows(#"[{"meeting_ringer":null}]"#) == nil)
        #expect(rows(#"[{"other":"mac"}]"#) == nil)
        #expect(rows(#"{"meeting_ringer":"mac"}"#) == nil)
        #expect(rows("not json") == nil)
        #expect(rows("") == nil)
    }

    @Test
    func theIslandRingsOnlyWhenItIsTheKnownOwner() {
        #expect(MeetingRinger.islandMayRing(.island))
        #expect(!MeetingRinger.islandMayRing(.mac))
        #expect(!MeetingRinger.islandMayRing(.iphone))
        #expect(!MeetingRinger.islandMayRing(nil))      // unreadable → quiet
    }
}
