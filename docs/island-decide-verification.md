# Grok 依頼の島内回答（1012-island-decide）

実装済み。SwiftPM ビルド・テストは未実行。2026-10-12 18:28–18:37 の load は19–71で、規約の8以下を満たさず、重い処理を開始していない。追加3テストの成功を報告してはいけない。

再開時は負荷と他のビルドを確認し、順番に実行する：

```sh
swift build
swift test --filter MitamaHumanTasksTests
```

検証済み：変更したSwiftファイルの `swiftc -frontend -parse`（終了0）、`git diff --check`（終了0）。実アプリ画面・実DBへの書き込みは未検証。push・PR・アプリ交換・再インストールなし。開始時のworktreeはclean。

変更ファイル：

- `Sources/OpenIslandCore/MitamaHumanTasks.swift`：外部依頼の取得、型を限定した回答・CAS・決定記録・relayジョブ・紐付け。
- `Sources/OpenIslandCore/MitamaNotifications.swift`：既存日時decoderを同一モジュール内で再利用。
- `Sources/OpenIslandApp/MitamaFeedCoordinator.swift`：既存ポーリングへの追加、二重押し防止、回答結果表示。
- `Sources/OpenIslandApp/Views/Island/IslandSessionListView.swift`：件数、展開して全文、外部入力と本人確認の注記、回答ボタン。
- `Sources/OpenIslandApp/AppModel.swift`：閉じた島・メニューの待ち件数へ追加。緊急通知が表示される場合もGrok件数を含める。
- `Tests/OpenIslandCoreTests/MitamaHumanTasksTests.swift`：CAS 0件・reject・approveのモック検証3件。
- 本ファイル。`AI_WORKLOG.md` は非コミット。

追加判断：CASには source=grok-relay も指定。IDは空・長過ぎ・フィルタを壊す文字を拒否。approveの空resume_objectiveはCAS前に拒否。決定記録が失敗してもHub同様にジョブ処理を続け、警告を表示。回答後のジョブ失敗は部分完了と表示し自動再投入しない。紐付け失敗時はジョブ登録済みと明示。取得失敗時は既存の待ちを保持。外部本文はプレーンテキスト表示。

既知の限界：CAS後の決定記録・ジョブ追加・紐付けはHub同様に複数リクエストであり、トランザクションではない。CAS勝者だけが投入するため二重回答での重複投入は防ぐが、通信断等の部分完了はHubで確認が必要。
