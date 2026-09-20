import Foundation
import Testing
@testable import OpenIslandCore

struct CodexGateLogTests {
    /// 台帳の行は 2026-09-19 の固定値なので、基準の「いま」も固定する。
    /// `Date()` と比べると、その日から 24 時間たった翌日以降は窓から外れて
    /// 必ず落ちる（実際 2026-09-20 に CI が落ちた）。
    private static let now = Date(timeIntervalSince1970: 1_789_822_800)  // 2026-09-19T13:00:00Z

    @Test("Empty lines returns empty dict")
    func emptyLines() {
        let now = Self.now
        let result = CodexGateLog.latestFailure(lines: [], now: now, window: 24 * 3600)
        #expect(result.isEmpty)
    }

    @Test("Pass clears failure")
    func passAfterFailClears() {
        let now = Self.now
        let lines = [
            #"{"ts":"2026-09-19T10:00:00Z","project":"mitama","branch":"main","gate":"fail","p1_count":2,"detail":"/path/to/detail"}"#,
            #"{"ts":"2026-09-19T11:00:00Z","project":"mitama","branch":"main","gate":"pass"}"#,
        ]
        let result = CodexGateLog.latestFailure(lines: lines, now: now, window: 24 * 3600)
        #expect(result["mitama"] == nil)
    }

    @Test("Failure after pass appears")
    func failureAfterPass() {
        let now = Self.now
        let lines = [
            #"{"ts":"2026-09-19T10:00:00Z","project":"mitama","branch":"main","gate":"pass"}"#,
            #"{"ts":"2026-09-19T11:00:00Z","project":"mitama","branch":"main","gate":"fail","p1_count":2,"detail":"/path/to/detail"}"#,
        ]
        let result = CodexGateLog.latestFailure(lines: lines, now: now, window: 24 * 3600)
        #expect(result["mitama"]?.p1Count == 2)
    }

    @Test("Oldest failure per project is ignored")
    func newestLineWins() {
        let now = Self.now
        let lines = [
            #"{"ts":"2026-09-19T10:00:00Z","project":"mitama","branch":"main","gate":"fail","p1_count":5,"detail":"/old"}"#,
            #"{"ts":"2026-09-19T11:00:00Z","project":"mitama","branch":"main","gate":"fail","p1_count":2,"detail":"/new"}"#,
        ]
        let result = CodexGateLog.latestFailure(lines: lines, now: now, window: 24 * 3600)
        #expect(result["mitama"]?.p1Count == 2)
        #expect(result["mitama"]?.detailPath == "/new")
    }

    @Test("Entries older than window are ignored")
    func olderThanWindowIgnored() {
        let now = Self.now
        let staleTime = now.addingTimeInterval(-(24 * 3600 + 1))
        let timeStr = ISO8601DateFormatter().string(from: staleTime)
        let lines = [
            #"{"ts":"\#(timeStr)","project":"mitama","branch":"main","gate":"fail","p1_count":2,"detail":"/path"}"#,
        ]
        let result = CodexGateLog.latestFailure(lines: lines, now: now, window: 24 * 3600)
        #expect(result.isEmpty)
    }

    @Test("Fresh entries within window appear")
    func freshEntryAppears() {
        let now = Self.now
        let freshTime = now.addingTimeInterval(-(12 * 3600)) // 12 hours ago
        let timeStr = ISO8601DateFormatter().string(from: freshTime)
        let lines = [
            #"{"ts":"\#(timeStr)","project":"mitama","branch":"main","gate":"fail","p1_count":3,"detail":"/path"}"#,
        ]
        let result = CodexGateLog.latestFailure(lines: lines, now: now, window: 24 * 3600)
        #expect(result["mitama"]?.p1Count == 3)
    }

    @Test("Unparsable lines are skipped")
    func unparsableLinesSkipped() {
        let now = Self.now
        let lines = [
            "not json at all",
            #"{"incomplete":"#,
            #"{"ts":"2026-09-19T10:00:00Z","project":"mitama","branch":"main","gate":"fail","p1_count":2,"detail":"/path"}"#,
        ]
        let result = CodexGateLog.latestFailure(lines: lines, now: now, window: 24 * 3600)
        #expect(result["mitama"]?.p1Count == 2)
    }

    @Test("Error result is neither pass nor fail")
    func errorResultIgnored() {
        let now = Self.now
        let lines = [
            #"{"ts":"2026-09-19T10:00:00Z","project":"mitama","branch":"main","result":"error","reason":"timeout"}"#,
        ]
        let result = CodexGateLog.latestFailure(lines: lines, now: now, window: 24 * 3600)
        #expect(result.isEmpty)
    }

    @Test("Timeout result is neither pass nor fail")
    func timeoutResultIgnored() {
        let now = Self.now
        let lines = [
            #"{"ts":"2026-09-19T10:00:00Z","project":"mitama","branch":"main","result":"timeout"}"#,
        ]
        let result = CodexGateLog.latestFailure(lines: lines, now: now, window: 24 * 3600)
        #expect(result.isEmpty)
    }

    @Test("Multiple projects tracked separately")
    func multipleProjects() {
        let now = Self.now
        let lines = [
            #"{"ts":"2026-09-19T10:00:00Z","project":"mitama-island","branch":"main","gate":"fail","p1_count":2,"detail":"/path1"}"#,
            #"{"ts":"2026-09-19T10:00:00Z","project":"mitama-os","branch":"main","gate":"fail","p1_count":3,"detail":"/path2"}"#,
        ]
        let result = CodexGateLog.latestFailure(lines: lines, now: now, window: 24 * 3600)
        #expect(result.count == 2)
        #expect(result["mitama-island"]?.p1Count == 2)
        #expect(result["mitama-os"]?.p1Count == 3)
    }

    @Test("Missing project field is skipped")
    func missingProjectSkipped() {
        let now = Self.now
        let lines = [
            #"{"ts":"2026-09-19T10:00:00Z","branch":"main","gate":"fail","p1_count":2,"detail":"/path"}"#,
        ]
        let result = CodexGateLog.latestFailure(lines: lines, now: now, window: 24 * 3600)
        #expect(result.isEmpty)
    }

    @Test("Missing branch field is skipped")
    func missingBranchSkipped() {
        let now = Self.now
        let lines = [
            #"{"ts":"2026-09-19T10:00:00Z","project":"mitama","gate":"fail","p1_count":2,"detail":"/path"}"#,
        ]
        let result = CodexGateLog.latestFailure(lines: lines, now: now, window: 24 * 3600)
        #expect(result.isEmpty)
    }

    @Test("Missing p1_count field is skipped")
    func missingP1CountSkipped() {
        let now = Self.now
        let lines = [
            #"{"ts":"2026-09-19T10:00:00Z","project":"mitama","branch":"main","gate":"fail","detail":"/path"}"#,
        ]
        let result = CodexGateLog.latestFailure(lines: lines, now: now, window: 24 * 3600)
        #expect(result.isEmpty)
    }

    @Test("Detail path can be nil")
    func detailPathNil() {
        let now = Self.now
        let lines = [
            #"{"ts":"2026-09-19T10:00:00Z","project":"mitama","branch":"main","gate":"fail","p1_count":2}"#,
        ]
        let result = CodexGateLog.latestFailure(lines: lines, now: now, window: 24 * 3600)
        #expect(result["mitama"]?.detailPath == nil)
    }
}
