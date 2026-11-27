import Darwin
import Foundation
import Testing
@testable import OpenIslandCore

struct BridgeBroadcastStallTests {
    private func rawConnect(_ socketURL: URL, rcvBuf: Int32 = 1024) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        try #require(fd >= 0)
        var size = rcvBuf
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &size, socklen_t(MemoryLayout<Int32>.size))
        do {
            try withUnixSocketAddress(path: socketURL.path) { address, length in
                try #require(Darwin.connect(fd, address, length) == 0)
            }
            try #require(receive(from: fd).contains { envelope in
                if case .hello = envelope { return true }
                return false
            })
        } catch {
            close(fd)
            throw error
        }
        return fd
    }

    private func register(_ fd: Int32) throws {
        try writeAll(BridgeCodec.encodeLine(.command(.registerClient(role: .observer))), to: fd)
        try #require(receive(from: fd) == [.response(.acknowledged)])
    }

    private func hook(_ index: Int) -> BridgeCommand {
        .processClaudeHook(ClaudeHookPayload(
            cwd: "/tmp/" + String(repeating: "x", count: 180),
            hookEventName: .sessionStart,
            sessionID: "stall-\(index)"
        ))
    }

    private func readable(_ fd: Int32, timeoutMs: Int32) -> Bool {
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        return poll(&pfd, 1, timeoutMs) > 0
    }

    private func receive(from fd: Int32) throws -> [BridgeEnvelope] {
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while readable(fd, timeoutMs: 500) {
            let count = read(fd, &buffer, buffer.count)
            try #require(count > 0)
            pending.append(buffer, count: count)
            let envelopes = try BridgeCodec.decodeLines(from: &pending)
            if !envelopes.isEmpty { return envelopes }
        }
        return []
    }

    @Test func stuckObserverIsDroppedAndOthersStillReceive() throws {
        let socket = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socket)
        try server.start()
        defer { server.stop() }

        let stuck = try rawConnect(socket)
        defer { close(stuck) }
        try register(stuck)

        let observer = try rawConnect(socket, rcvBuf: 65536)
        defer { close(observer) }
        try register(observer)

        let start = ContinuousClock.now
        let hookClient = BridgeCommandClient(socketURL: socket)
        for index in 0..<120 {
            try #require(hookClient.send(hook(index), timeout: 2) == .acknowledged)
            let envelopes = try receive(from: observer)
            try #require(envelopes.contains { envelope in
                guard case let .event(.sessionStarted(event)) = envelope else { return false }
                return event.sessionID == "stall-\(index)"
            })
        }
        #expect(start.duration(to: .now) < .seconds(5))

        // Stuck client was removed by the server: draining it reaches EOF.
        var buffer = [UInt8](repeating: 0, count: 65536)
        var sawEOF = false
        while readable(stuck, timeoutMs: 500) {
            let n = read(stuck, &buffer, buffer.count)
            if n == 0 { sawEOF = true; break }
            if n < 0 { break }
        }
        #expect(sawEOF)
    }

    @Test func unregisteredConnectionDoesNotReceiveBroadcast() throws {
        let socket = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socket)
        try server.start()
        defer { server.stop() }

        let silent = try rawConnect(socket, rcvBuf: 65536)
        defer { close(silent) }

        _ = try BridgeCommandClient(socketURL: socket).send(hook(0))
        #expect(!readable(silent, timeoutMs: 300))
    }

    @Test func writeAllThrowsAfterDeadlineOnFullSocket() throws {
        var fds: [Int32] = [0, 0]
        try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        defer { close(fds[0]); close(fds[1]) }
        try makeSocketNonBlocking(fds[0])

        let chunk = Data(repeating: 0x41, count: 65536)
        let start = Date()
        #expect(throws: BridgeTransportError.self) {
            while true { try writeAll(chunk, to: fds[0], timeout: 0.1) }
        }
        #expect(Date().timeIntervalSince(start) < 2)
    }
}
