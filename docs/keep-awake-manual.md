# 手動「起こしておく」実装報告

ブランチ: `feat/keep-awake-manual`。コミット・push・PR・マージは未実施（親担当）。

## 操作

メニューバーの「起こしておく」からオフ・1時間・3時間・8時間・無期限・エージェントの作業が終わるまでを選ぶ。時間指定中は残り分数と「止める」を表示する。島ヘッダーのカップは1時間開始／停止の切替。詳細時間はメニューで指定する。

一般設定の「画面も消さない」「ふたを閉じても止めない」は既定オフ。自動保持の設定と判定条件は維持し、手動・自動のどちらかが保持を要求すればシステムのアイドルスリープを防ぐ。画面保持は手動モードだけに適用する。

手動状態・開始時刻・画面／ふたの設定は既存の設定ストアへ保存する。再起動時に期限を再判定し、無期限は継続する。熱が serious/critical、バッテリー20%未満、ふた閉じ＋バッテリーでは手動状態をオフへ戻し、島に一度通知する。電源と期限は5秒ごと、熱とセッション・設定変更は変更時にも再判定する。メニューを開いていてもタイマーは動作する。

ふた閉じ保持は手動モードかつAC接続中だけ。初回オン時だけ管理者認証で `/etc/sudoers.d/mitama-island-pmset` を作成する。ユーザー名は `NSUserName()` を英数字・`.`・`_`・`-` のみに検証し、対象ユーザーに `/usr/bin/pmset -a disablesleep 0` と `1` の2コマンドだけ NOPASSWD を許可する。root管理の一時ファイルへ書き、`visudo -cf` 成功後に root:wheel・0440 で install する。一時ファイルは成功・失敗とも削除する。ファイルが存在する間は再作成しない。作成失敗・不正ユーザー名は従来の認証方式へ戻る。変更・復元はシェルを通さない `Process` の `sudo -n /usr/bin/pmset -a disablesleep N` を先に試し、失敗時だけ管理者ダイアログを出す。停止・期限・安全弁・AC切断・アプリ終了時は `0` へ戻す。変更前にUserDefaultsへ記録し、次回起動で `pmset -g` の SleepDisabled を確認して復元する（off時はキー省略も認識）。復元に失敗した記録は消さない。終了時の復元を拒否した場合は終了を取り消し、手動オフで監視を再開する。再試行はメニューの「オフ」を選ぶか、アプリ終了を再実行する。

設定の「この許可を外す」はふた保持設定をオフにして復元完了を待ち、管理者認証で sudoers ファイルを削除する。復元失敗時は許可を残す。削除後に再度オンにすると初回認証が必要。4言語の説明とボタンを追加。

## 今回のふた閉じ復元修正の検証

- `swift build --disable-sandbox --cache-path /tmp/island-swift-cache`: 成功。
- `swift test --disable-sandbox --cache-path /tmp/island-swift-cache --filter KeepAwake`: 14件成功。既存12件を維持し、ユーザー名拒否と2コマンドだけのsudoers本文の2件を追加。
- 生成形式を `/usr/sbin/visudo -cf` で検証し parsed OK。実際の `/etc/sudoers.d` は変更していない。
- 権限ダイアログ、許可作成・解除、ふた閉じ中のAC切断は実機未検証。許可作成失敗時は従来方式のため復元に認証が必要になる。
- install はroot管理の一時ファイルを0440へ整えてからrenameし、途中失敗で不完全な許可ファイルを公開しない。
- ユーザー指示に従いコミット・追加委譲は行っていない。

## 前回実装時の検証

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
7. ふた閉じ保持中に電源を抜き、認証ダイアログなしで5秒程度以内に SleepDisabled が0へ戻り、スリープすることを実機で確認する。
8. 「この許可を外す」で復元・sudoers削除を確認し、再オン時の再認証、初回認証キャンセル時の従来方式へのフォールバックも確認する。
9. 無期限の再起動継続、期限超過後のオフ、復元認証キャンセル時の記録保持と再試行を確認する。

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

## 常時稼働（Mac mini の代わり）

メニュー先頭の「常時稼働（Mac mini の代わり）」は期限なし。選択中は「起こしておく · 常時稼働」と表示する。画面保持は既存設定に従い、ふた保持設定・AC接続の有無に関係なくふた閉じ保持を有効にする。初回は既存の preparePermission で sudoers を用意する。保存済みのモードは起動時も再開する。

熱 serious/critical またはバッテリー駆動で25%未満になると、モードを残してアイドル保持・画面保持・disablesleep を一時解除する。解除中は自動保持より安全弁を優先する。熱 nominal/fair かつ AC接続または残量30%以上になれば自動再開する。解除・再開の各遷移で島へ一度通知する。既存モードの20%未満・バッテリーふた閉じでオフへ戻す挙動は維持する。

実機での管理者認証、ふた閉じ、熱・残量による解除と復帰、再起動後の保持は別途確認が必要。

### 常時稼働の検証結果

- `bash scripts/harness.sh lint`：成功（5件、4言語886キー一致）。
- `bash scripts/check-docs.sh`：成功。`git diff --check`：成功。
- `swift build`：sandbox-exec の `sandbox_apply: Operation not permitted` で失敗。指示に従い回避せず停止。
- `swift test --filter KeepAwake`：未実行。追加4件（ふた閉じ、電池ヒステリシス、熱復帰、永続化・無期限・表示設定）も未検証。
- コミット・追加委譲なし。親担当でビルド・テストと実機検証が必要。
