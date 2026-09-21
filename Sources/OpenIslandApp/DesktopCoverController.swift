import AppKit
import OpenIslandCore

/// 画面共有中に机を隠す1枚。
///
/// デスクトップのアイコンのすぐ上に置く。普通の窓より下なので、作業中の画面は
/// 何も変わらず、机を見せたときだけ無地になる。マウスは素通しにしてあるので、
/// 敷いてあることに気づかずデスクトップをクリックしても今までどおり動く。
@MainActor
final class DesktopCoverController {
    private var panels: [NSPanel] = []

    var isCovering: Bool { !panels.isEmpty }

    /// 机の色。壁紙を隠すのが目的ではないので、真っ黒ではなく落ち着いた地にする。
    private static let coverColor = NSColor(calibratedWhite: 0.07, alpha: 1.0)

    /// デスクトップのアイコンのすぐ上。ここより上げると普通の窓を覆ってしまう。
    private static var level: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    func apply(shouldCover: Bool) {
        shouldCover ? cover() : uncover()
    }

    private func cover() {
        let screens = NSScreen.screens
        // 画面の枚数が変わったら敷き直す。外付けを挿したときに片方だけ
        // 隠れたままになるのを避ける。
        if panels.count == screens.count, !panels.isEmpty { return }
        uncover()

        panels = screens.map { screen in
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = Self.level
            panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .stationary]
            panel.isOpaque = true
            panel.backgroundColor = Self.coverColor
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.isReleasedWhenClosed = false
            panel.setFrame(screen.frame, display: true)
            panel.orderFront(nil)
            return panel
        }
    }

    private func uncover() {
        for panel in panels { panel.orderOut(nil) }
        panels = []
    }
}
