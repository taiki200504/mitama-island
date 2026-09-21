import Foundation
import Observation

/// 手のジェスチャを「練習」するための場所。
///
/// カメラの前で二本指を振っても、当たっているのか外しているのかが分からない
/// ——島が開けば当たり、開かなければ**ポーズが違うのか、カメラが見ていないのか、
/// そもそも機能が切れているのか**が区別できない。ここはその区別のためだけに
/// あり、認識したものを名前で並べる。島は開かないし、何も起きない。
@MainActor
@Observable
final class CameraGestureRehearsal {
    /// 見つけたもの。参照のジェスチャと 1 対 1 で対応する。
    enum Sighting: String, Equatable, Sendable, CaseIterable {
        case swipeDown
        case swipeUp
        case palm
        case pinch
        case pointing

        /// `Localizable.strings` の引き。
        var labelKey: String { "camera.sighting.\(rawValue)" }
    }

    struct Entry: Identifiable, Equatable, Sendable {
        let id: UUID
        let sighting: Sighting
        let at: Date
    }

    /// 新しいものが先頭。
    private(set) var entries: [Entry] = []
    private(set) var isRunning = false

    /// 画面に残す数と、さかのぼる長さ。指差しは毎フレーム来るので、
    /// 古いものを落とさないと一覧が指差しだけで埋まる。
    static let visibleLimit = 8
    static let window: TimeInterval = 60

    /// 同じものが連続したときにまとめる間隔。指差しは 1 秒に何度も来る。
    static let coalescingInterval: TimeInterval = 0.8

    @ObservationIgnored private var stopTask: Task<Void, Never>?

    /// 練習を始める。`seconds` 経ったら `onTimeout` を呼んで自分も止まる。
    func start(seconds: TimeInterval, onTimeout: @escaping @MainActor () -> Void) {
        stopTask?.cancel()
        entries = []
        isRunning = true
        stopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.isRunning = false
            self?.stopTask = nil
            onTimeout()
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        isRunning = false
    }

    /// 認識したものを 1 つ足す。練習中でなければ何もしない。
    func record(_ sighting: Sighting, at now: Date = Date()) {
        guard isRunning else { return }
        entries = Self.recording(sighting, at: now, into: entries)
    }

    /// 足し方そのもの。時刻を渡せる純関数にしてあるのは、ここがこの型の
    /// 唯一の判断（まとめる・古いものを落とす）だから。
    static func recording(_ sighting: Sighting, at now: Date, into entries: [Entry]) -> [Entry] {
        // 直前と同じものが立て続けに来たら、時刻だけ新しくして 1 件に保つ。
        if let head = entries.first,
           head.sighting == sighting,
           now.timeIntervalSince(head.at) < coalescingInterval {
            var updated = entries
            updated[0] = Entry(id: head.id, sighting: sighting, at: now)
            return updated
        }
        let fresh = Entry(id: UUID(), sighting: sighting, at: now)
        return pruned([fresh] + entries, now: now)
    }

    /// 古いものと、あふれたものを落とす。
    static func pruned(_ entries: [Entry], now: Date) -> [Entry] {
        entries
            .filter { now.timeIntervalSince($0.at) <= window }
            .prefix(visibleLimit)
            .map { $0 }
    }
}
