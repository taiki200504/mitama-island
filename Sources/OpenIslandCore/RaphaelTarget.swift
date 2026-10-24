import Foundation

/// どのラファエルを `raphaelctl` で操作しているか。登録済みの LaunchAgent を正本にして決める。
///
/// 旧 `raphaelctl` は `~/Applications/Raphael.app` と bridge のポート 8770 を前提にしている。
/// mitama-os 版（`Raphael-mitama-os.app`）は同じラベルの LaunchAgent で `COMPANION_PORT` を変えて動くので、
/// 旧 `raphaelctl on` を呼ぶと旧アプリの常駐へ書き戻してしまう。だから旧アプリと確かめられた時だけ on/off を通す。
///
/// plist からは「既知の2つの実行ファイルのどちらか」と「ポートの数字」だけを読む。plist の値を実行・展開しない。
public enum RaphaelTarget: Sendable, Equatable {
    /// 旧アプリ（または mitama-os 版が無い Mac）。今までどおり。
    case legacy
    /// mitama-os 版が常駐として登録されている。ミュートはこのポートの bridge へ知らせる。on/off は島から行わない。
    case mitamaOS(port: Int)
    /// mitama-os 版が置かれているのに常駐の登録が無い・見知らぬ実行ファイルが登録されている。on/off は島から行わない。
    case unmanaged

    public static let label = "com.mishima.raphael"
    static let legacyExecutable = "Applications/Raphael.app/Contents/MacOS/Raphael"
    static let mitamaOSExecutable = "Applications/Raphael-mitama-os.app/Contents/MacOS/Raphael"
    static let defaultPort = 8770

    /// - Parameters:
    ///   - plist: `~/Library/LaunchAgents/com.mishima.raphael.plist` の中身（無ければ nil）。
    ///   - mitamaOSAppInstalled: `~/Applications/Raphael-mitama-os.app` があるか。
    ///   - home: 本人のホーム（末尾の / 無し）。
    public static func resolve(plist: Data?, mitamaOSAppInstalled: Bool, home: String) -> RaphaelTarget {
        guard let plist else { return mitamaOSAppInstalled ? .unmanaged : .legacy }
        guard let dict = (try? PropertyListSerialization.propertyList(from: plist, format: nil)) as? [String: Any],
              dict["Label"] as? String == label,
              let args = dict["ProgramArguments"] as? [String], args.count == 1 else { return .unmanaged }
        switch args[0] {
        case "\(home)/\(legacyExecutable)":
            return .legacy
        case "\(home)/\(mitamaOSExecutable)":
            let env = dict["EnvironmentVariables"] as? [String: Any]
            guard let raw = env?["COMPANION_PORT"] else { return .mitamaOS(port: defaultPort) }
            guard let text = raw as? String, let port = parsePort(text) else { return .unmanaged }
            return .mitamaOS(port: port)
        default:
            return .unmanaged
        }
    }

    /// bridge.py と同じ範囲（数字だけ・1024〜65535）。
    static func parsePort(_ text: String) -> Int? {
        guard !text.isEmpty, text.count <= 5, text.allSatisfy(\.isASCII), text.allSatisfy(\.isNumber),
              let port = Int(text), (1024...65535).contains(port) else { return nil }
        return port
    }

    /// 島から on/off を出してよいか（旧アプリの時だけ）。
    public var allowsOnOff: Bool { self == .legacy }

    /// `raphaelctl` に渡す環境の上書き。bridge への知らせを正しいポートへ向ける。
    public var environmentOverrides: [String: String] {
        if case let .mitamaOS(port) = self { return ["COMPANION_PORT": String(port)] }
        return [:]
    }
}
