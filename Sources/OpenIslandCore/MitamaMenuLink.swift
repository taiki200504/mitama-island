import Foundation

/// 新しい Mac のメニューアプリ(mitama-os の MitamaMac)を、島から呼ぶ小さな口。
///
/// メニューバーのアイコンはノッチの陰に隠れると押せないので、島のパネルからこのリンクで同じメニューの窓を開く。
/// 受け口は mitama-os の `MenuOpenLink`(スキーム `app.mitama.os.mac.menu`・ホスト `open`)。開くのは相手の画面だけで、何も送らない。
public enum MitamaMenuLink {
    public static let scheme = "app.mitama.os.mac.menu"
    public static let url = URL(string: "\(scheme)://open")!
}
