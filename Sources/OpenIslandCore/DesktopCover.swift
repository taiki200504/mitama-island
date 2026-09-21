import Foundation

/// 画面共有中に机（デスクトップのアイコン）を隠すかどうか。
///
/// 隠し方として Finder の `CreateDesktop` を書き換えて `killall Finder` する
/// やり方もあるが、採らない。人の設定を書き換えて Finder を落とすのは、
/// 共有が終わったあとに元へ戻す保証が無く、開いていた Finder の窓も消える。
/// 代わりに、デスクトップのアイコンの上・普通の窓の下に1枚敷く。
public enum DesktopCover: Sendable {
    /// 共有が「確かに起きている」ときだけ隠す。
    ///
    /// 読めなかった（`.unavailable`）ときは隠さない。共有していないのに机が
    /// 消えるのは事故でしかなく、逆に一度余計に映るのは見られて困るものを
    /// 置いていた人の問題として取り返しがつく。
    public static func shouldCover(scene: QuietSceneSnapshot, isEnabled: Bool) -> Bool {
        isEnabled && scene.screenIsBeingShared == .active
    }
}
