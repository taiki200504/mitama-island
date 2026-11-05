import AppKit
import Foundation
import Testing
import OpenIslandCore
@testable import OpenIslandApp

/// 分散通知の代わりに普通の `NotificationCenter` へ合成の通知を出す。受け取りは次の main の番なので待って確かめる。
@MainActor
struct JarvisSummonWatcherTests {
    private static let name = Notification.Name(JarvisSummon.notificationName)

    private func poll(timeout: Duration = .seconds(2), until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("Valid summons arrive once; malformed and repeated ones do not")
    func filtersAndDedupes() async throws {
        let center = NotificationCenter()
        let watcher = JarvisSummonWatcher(center: center)
        var received: [JarvisSummon] = []
        watcher.onSummon = { received.append($0) }
        watcher.start()
        watcher.start()   // 二度呼んでも観測は1つ

        center.post(name: Self.name, object: nil, userInfo: ["request": "", "state": "listening"])
        center.post(name: Self.name, object: nil, userInfo: ["request": "", "state": "listening"])
        center.post(name: Self.name, object: nil, userInfo: ["request": "", "state": "approve"])
        center.post(name: Self.name, object: nil, userInfo: ["request": "", "state": "done", "text": "本文"])
        center.post(name: Self.name, object: nil, userInfo: ["request": "", "state": "acking"])
        try await poll { received.count >= 2 }
        try await Task.sleep(for: .milliseconds(50))

        #expect(received == [
            JarvisSummon(requestID: nil, state: .listening),
            JarvisSummon(requestID: nil, state: .acking),
        ])
    }

    @Test("A stopped watcher no longer hears summons")
    func stopRemovesObserver() async throws {
        let center = NotificationCenter()
        let watcher = JarvisSummonWatcher(center: center)
        var count = 0
        watcher.onSummon = { _ in count += 1 }
        watcher.start()
        watcher.stop()
        center.post(name: Self.name, object: nil, userInfo: ["request": "", "state": "listening"])
        try await Task.sleep(for: .milliseconds(50))
        #expect(count == 0)
    }

    @Test("Only listening and results open the island, with the voice reason; the line follows every state")
    func presentOpensOnlyForListeningAndResults() {
        _ = NSApplication.shared
        let model = isolatedAppModel()
        model.disablesOverlayEventMonitoringDuringHarness = true
        defer { model.notchClose() }
        let request = UUID()

        model.presentJarvisSummon(JarvisSummon(requestID: request, state: .running))
        #expect(model.notchStatus == .closed)
        #expect(model.jarvisSummon?.state == .running)

        model.presentJarvisSummon(JarvisSummon(requestID: nil, state: .listening))
        #expect(model.notchStatus == .opened)
        #expect(model.notchOpenReason == .voice)
        #expect(model.jarvisSummon?.state == .listening)

        model.notchClose()
        model.presentJarvisSummon(JarvisSummon(requestID: request, state: .acking))
        #expect(model.notchStatus == .closed)
        model.presentJarvisSummon(JarvisSummon(requestID: request, state: .done))
        #expect(model.notchStatus == .opened)
        #expect(model.jarvisSummon == JarvisSummon(requestID: request, state: .done))
    }

    @Test("A voice summon routes to the plain session list")
    func voiceRoute() {
        #expect(IslandOpenedRouting.route(reason: .voice, surface: .sessionList(), firstActionableID: "s1")
                == .sessionList(highlight: nil))
    }
}
