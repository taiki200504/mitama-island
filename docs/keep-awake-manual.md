# 手動「起こしておく」実装報告

ブランチ: `feat/keep-awake-manual`。コミット・push・PR・マージは未実施（親担当）。

## 操作

メニューバーの「起こしておく」からオフ・1時間・3時間・8時間・無期限・エージェントの作業が終わるまでを選ぶ。時間指定中は残り分数と「止める」を表示する。島ヘッダーのカップは1時間開始／停止の切替。詳細時間はメニューで指定する。

一般設定の「画面も消さない」「ふたを閉じても止めない」は既定オフ。自動保持の設定と判定条件は維持し、手動・自動のどちらかが保持を要求すればシステムのアイドルスリープを防ぐ。画面保持は手動モードだけに適用する。

手動状態・開始時刻・画面／ふたの設定は既存の設定ストアへ保存する。再起動時に期限を再判定し、無期限は継続する。熱が serious/critical、バッテリー20%未満、ふた閉じ＋バッテリーでは手動状態をオフへ戻し、島に一度通知する。電源と期限は5秒ごと、熱とセッション・設定変更は変更時にも再判定する。メニューを開いていてもタイマーは動作する。

ふた閉じ保持は手動モードかつAC接続中だけ。OSの管理者認証で `/usr/bin/pmset -a disablesleep 1` を実行する。停止・期限・安全弁・AC切断・アプリ終了時は `0` へ戻す。変更前にUserDefaultsへ記録し、次回起動で `pmset -g` の SleepDisabled を確認して復元する（off時はキー省略も認識）。復元に失敗した記録は消さない。終了時の復元を拒否した場合は終了を取り消し、手動オフで監視を再開する。再試行はメニューの「オフ」を選ぶか、アプリ終了を再実行する。

## 検証

- `swift build --disable-sandbox --cache-path /tmp/island-swift-cache`: 成功。
- `swift test --disable-sandbox --cache-path /tmp/island-swift-cache --filter KeepAwake`: 追加前2件 → 追加後12件、全件成功。
- 追加10件は既存の `Tests/OpenIslandCoreTests` ターゲット内。期限境界（1/3/8時間）、熱、電池19%／20%、ふた閉じと電源、作業終了、無期限、画面保持、デスクトップ、安全通知対象を検証。
- SwiftPMがこの環境の入れ子sandboxを作れないため `--disable-sandbox` と書き込み可能なキャッシュを指定。既存のコンパイラ警告は残る。
- 権限ダイアログ、実機のふた閉じ、再起動後の復元は未実施。管理者認証が拒否された場合、OS設定の復元を強制することはできない。

## 手で確かめる手順

1. 現在のブランチからアプリを起動する（bundle確認時は `zsh scripts/launch-dev-app.sh`）。
2. メニューバーの「起こしておく」→「1時間」を選ぶ。
3. `pmset -g assertions` で `Mitama Island: stay awake` と `PreventUserIdleSystemSleep` が表示されることを確認する。
4. 「画面も消さない」をオンにし、同じコマンドで `PreventUserIdleDisplaySleep` も確認する。
5. 「止める」で手動分が消えることを確認する。自動保持がオンで作業中ならシステム保持は継続するため、手動分だけを確認する場合は自動保持をオフにする。
6. AC接続中に「ふたを閉じても止めない」をオンにして手動モードを開始し、OS認証後 `pmset -g` の SleepDisabled が1になることを確認する。停止・終了後は0または項目省略を確認する。
7. 無期限で再起動して継続、時間指定の期限超過後に再起動してオフ、AC切断時のふた保持解除を確認する。復元認証のキャンセル時は記録が残り、再試行で解除されることも確認する。

## 変更ファイル

- `Sources/OpenIslandCore/ManualKeepAwakePolicy.swift`
- `Sources/OpenIslandApp/AppModel+KeepAwake.swift`
- `Sources/OpenIslandApp/AppModel.swift`
- `Sources/OpenIslandApp/KeepAwakeController.swift`
- `Sources/OpenIslandApp/LidSleepController.swift`
- `Sources/OpenIslandApp/OpenIslandApp.swift`
- `Sources/OpenIslandApp/Settings/BehaviourSettings.swift`
- `Sources/OpenIslandApp/StatusItemController.swift`
- `Sources/OpenIslandApp/Views/Island/IslandOpenedHeaderView.swift`
- `Sources/OpenIslandApp/Views/Island/IslandPanelView.swift`
- `Sources/OpenIslandApp/Views/Settings/Panes/GeneralSettingsPane.swift`
- `Sources/OpenIslandApp/Resources/ja.lproj/Localizable.strings`
- `Sources/OpenIslandApp/Resources/en.lproj/Localizable.strings`
- `Sources/OpenIslandApp/Resources/zh-Hans.lproj/Localizable.strings`
- `Sources/OpenIslandApp/Resources/zh-Hant.lproj/Localizable.strings`
- `Tests/OpenIslandCoreTests/ManualKeepAwakePolicyTests.swift`
- `docs/product.md`
- `docs/keep-awake-manual.md`

作業台帳 `AI_WORKLOG.md` はコミット対象外。

## 親担当のコミットメッセージ

```text
feat(keep-awake): 手動で起こしておくモード（Amphetamine 相当）

Task: 1015-keepawake
Agent: codex
```
