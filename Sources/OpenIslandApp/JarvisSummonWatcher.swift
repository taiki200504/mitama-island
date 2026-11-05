import Foundation
import OpenIslandCore

/// Raphael.app の「ジャービス」の呼びかけを分散通知で受ける。
///
/// 受け口はこの1つの名前だけ。中身が決まった形でなければ黙って捨て、同じ通知が続けば1回にまとめる。
/// 島が動いていなければ通知は誰にも届かない（島を起こさない）。
/// 島はふだん前面に出ない（非アクティブ）ので、分散通知は `.deliverImmediately` で受ける。
/// 既定のままだと非アクティブの間は保留され、呼びかけても開かない。
/// 試験では `DistributedNotificationCenter` の代わりに普通の `NotificationCenter` を渡す。
@MainActor
final class JarvisSummonWatcher: NSObject {
    private static let name = Notification.Name(JarvisSummon.notificationName)

    var onSummon: ((JarvisSummon) -> Void)?

    private let center: NotificationCenter
    private let now: () -> Date
    private var deduper = JarvisSummonDeduper()
    private var started = false

    init(center: NotificationCenter = DistributedNotificationCenter.default(), now: @escaping () -> Date = Date.init) {
        self.center = center
        self.now = now
        super.init()
    }

    func start() {
        guard !started else { return }
        started = true
        if let distributed = center as? DistributedNotificationCenter {
            distributed.addObserver(self, selector: #selector(handle(_:)), name: Self.name, object: nil,
                                    suspensionBehavior: .deliverImmediately)
        } else {
            center.addObserver(self, selector: #selector(handle(_:)), name: Self.name, object: nil)
        }
    }

    @objc nonisolated private func handle(_ note: Notification) {
        // userInfo は Sendable でないので、ここで固定の形に読んでから main へ渡す。
        let summon = JarvisSummon.parse(userInfo: note.userInfo)
        Task { @MainActor [weak self] in
            guard let self, let summon else { return }
            self.receive(summon)
        }
    }

    func receive(_ summon: JarvisSummon) {
        guard deduper.accept(summon, at: now()) else { return }
        onSummon?(summon)
    }

    func stop() {
        center.removeObserver(self, name: Self.name, object: nil)
        started = false
    }

    isolated deinit {
        center.removeObserver(self)
    }
}
