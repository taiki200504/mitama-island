# Upstream PR取り込み 2026-11-07

対象: taiki200504/mitama-island、branch feat/upstream-picks-1106。
親エージェントが同worktreeで origin/main の git pull --ff-only 成功を確認した後に実施。
upstream Octane0411/open-vibe-island はローカル取得済みコミットだけを参照。リモート操作なし。

## 取り込み

- #708: 8af6984e → 7ad86812。削除済みIslandPanelViewを復活させず、IslandCompletionActionViewへ560pt上限を移植。
- #707: 19f1adc2 → 33ab12d7。プロンプト優先見出し、端末バッジにworkspaceを追加。既存のPaseoタイトル・自動命名を維持し、削除済み旧画面のレイアウト変更は取り込まない。既存の日本語テストヘルパーを保持。
- #709: 199a50be / 289fc674 / f48cf4b6 / 688c9b8b → 610a5624 / ca659e5a / c76bfd0f / 55f44048。tmux switch-client削除、VS Code・解決済みbundle IDへの復帰、停止端末の誤起動防止。現行cmux対応を保持し、追加テストを現行XCTestへ変換。
- #718: 773f4223 → 773e50f3。古いCodexスレッドの件数除外。テスト用AppModelの隔離を保持。

## Skip

- #636: 全4コミットskip。既存UsageSettings.valueMode / UsageValueMode.displayedPercentageで使用量・残量の切替、0...100 clamp、消費量基準の色分けが実装済み。旧画面と別UserDefaultsキーの設定を復活すると二重管理になる。既存テストはTests/OpenIslandCoreTests/UsagePresentationTests.swift。
- #681: 全2コミットskip。現行UsageSettings.showResetCardsで全期間・各リセット時刻表示が実装済み。現行のコンパクト既定値(false)と上流のdetailed既定値が競合し、削除済み旧設定画面・旧島画面を復活させる必要があるため現行仕様を優先。

## 検証と残作業

- git diff origin/main...HEAD --check: 成功。
- Swiftテスト: 未実行。sandboxでsysctl vm.swapusageがOperation not permitted、heavyの必須ロック ~/.claude/state/heavy-queue もOperation not permitted。ローカル権限実行の審査待ちを終了し、テストプロセスは起動していない。
- .buildなし。依存取得にはネットワークまたは既存キャッシュが必要。sandboxからgithub.comはDNS解決不可。
- 親側で負荷確認・heavyロックを通し、関連テスト AgentSessionPresentationTests / TerminalJumpServiceTests / AppModelSessionListTests / CodexSessionTrackingTests を先に、全体swift testを最後に1回実行。nice 15、jobs 1。
- UI実画面・Jev未検証。pushとtaiki200504/mitama-islandへのPR作成は親側担当。マージなし。
