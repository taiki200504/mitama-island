# 1005 Island 全体改善・受入記録

対象: local常用 Mitama Island、外部リリースなし。基準8732910 / 1297。全体検証・3260405時点、常用更新1303（最終表示修正の検証中）。
目的: 誰のどの会話が何を待つか分かり、島で回答・承認・会話への移動ができる。

## 実装と受入

- 一覧・件数・切替は同じ可視集合を使用。子の通常許可は親の仕事として独立行を増やさず、子の質問は親カードへ表示し、元の子のSDK要求に回答。親自身の確認が先の場合も子の要求を保持し、解決後に表示する。
- 質問を先頭に置き、会話名・作業場所・質問元・実モードを表示。単一・複数・自由入力の選択状態をAXに公開。長いカードは実際の残り高さでスクロールし、最小設定280でも送信と会話を開くボタンへ到達。
- 失敗時は入力と要求を保持して再送可能。新しい要求IDでは入力・親の送信状態・エラーをリセットし、古い応答が新しい質問へ混ざらない。未対応形式は手動でPaseoを開く導線を残し、架空の許可ボタンを作らない。
- 会話への移動はクリックごとに現サーバIDと正確なnative agent IDを検証。古い・終了・不明な対象を成功扱いしない。
- 閉じた島はAXボタンから開く。承認キーは開いている対象にだけ登録し、設定と入力ソース変更へ追従。明示的な会話移動はクリック移動を無効にしても利用可能。
- 設定は同じモデルと保存元を使い、12分類の検索、空結果、クリア、選択保持、実コンポーネントのプレビュー、Paseoの実接続状態と再試行を追加。Paseoへ適用されないフォルダ自動許可と未実装キーは隠し、説明も適用範囲を明記。
- Codex利用量監視のON/OFF、通知の初回依頼フィルタ、静かな場面での状態保持、音声・カメラのキャンセル後callback、タイマー終了と質問期限を回帰テスト。Now Playingの非対応環境では使えないヘッダー操作を隠して設定で説明。
- 元配布元の自動更新/feedを無効化。ローカル署名、資産PNGの既存変更を保護。Paseo/Claudeの停止や再起動、ユーザーのカメラ・マイク・Focus権限変更は行っていない。

## 自動検証

最終全体テスト `/tmp/mitama-island-1005-final-reconcile-tests.log`: Core810、App645、XCTest34、合計1489件。1488PASS、Ghostty実機ジャンプ環境依存1SKIP、失敗0。
親の確認中に子の質問が来る同時状態、失敗後の再試行、新しいIDでの入力リセット、通信失敗と復帰、unknown/orphan、正確な回答先、キー/表示集合、設定同期を含む。
FocusTimer・SneakPeekの時間依存テストは時計/完了イベントを注入し、並列実行の偶然で通さない。

## native CUA検証

- 通常アプリから実Claude AskUserQuestion（bypassPermissions）を親カードに表示。「表示テスト完了」を選んで送信したあと、native agentが `ISLAND_SDK_LIVE_TEST_OK: 表示テスト完了` を返したことをMCPのactivityで照合。対象はテスト専用の子45e6c730-b85d-4844-8db9-39551324447f。ユーザー自身のGrok Bot/dots等の回答は行っていない。
- その質問の「Paseoで開く」をクリックし、Paseoの実ウィンドウタイトルと選択会話が「Island SDK回答テスト」になったことをAXで照合。アプリを前面にしただけを成功扱いしていない。
- isolated長文/親子fixture: 8番目の選択肢、複数選択、自由入力、3問完了、送信失敗で全入力保持、再送成功でカード消失。実daemonへ送らない専用mockを使用。
- release1298長文親子fixture: 親1件、子の質問元、3問中0問の日本語順序、560pxと280pxで最下部送信/会話移動へ到達。設定は560へ戻した。
- release1299で同じ本文/選択肢の新要求IDへ切り替わると旧選択が未選択へ戻り、再選択/送信が成功。unknown形式は説明と会話移動だけを表示し内部ツール名と許可ボタンを隠す。
- 常用1299の起動、実Paseo接続済み、利用不可の再生アイコン非表示、閉状態AXから一覧を開く、設定検索Paseo・空結果・クリア・選択保持、接続表示、実カードプレビューを実操作。
- native artifact: `output/1005-overhaul/final-parent-long/` にoverlay.png、overlay.ax.json、report.json、timeline.json。旧before/初期afterは比較用で、最終成功の証拠と混同しない。

## Full access / Bypassの範囲

同時進行のPaseo側タスクがpaseo-autoの子モード未継承を修正（`../paseo-sandbox/permission-mode-fix-result.md`）。既存の生存セッションを勝手に昇格せず、新規子でFullAccess/Bypass継承を検証。こちらでもFullAccessのlist_agents/get_agent_status/list_pending_permissionsを実行し、追加承認0を確認。Claudeの上記実質問もBypass継承を確認。
MCPの個別trustと本人の選択質問は実行sandboxモードとは別。島はモード名だけを根拠に、未知のMCP承認を自動で一括許可しない。Paseoが実際に提示する選択肢と許可範囲を送る。

## 独立レビューと限界

実Grok4.7による初回批評を `1005-independent-critique.md` に保存。指摘を統合し、別Codexの最終批評で親状態と入力更新の2件を修正。実Grok4.7の最終レビューはb4bdc21でコード上blocker0。
最終Grokが挙げた未検証3点のうち、実Paseo会話移動は上記native検証、親自身の確認と子質問の同時状態は5263264の回帰テストで解消。
画面共有・OSロック・Focusが切り替わる瞬間の既に開いたカードは実OS遷移で未検証。ユーザー端末をロックせず、ユニットで通知抑制とデータ保持を検証。Codex async質問の実送信は当該テスト子がツールを公開せず未検証で、native payload mockの回帰テストとClaude live検証を区別する。外部ディスプレイ全種類、全般WCAG適合、万人の好みや「完璧」は主張しない。

## 分担

experience UI・settings integration・interactions/privacyは専用worktreeで並行。rootは設計、統合、負荷を抑えた直列テスト/ビルド、CUA受入とローカル反映。外部公開なし。

最終文字列検査は4言語852キー一致、docs・10設定能力・resource・21sound検査PASS、補助Python5件PASS。artifact validatorの自動smoke時間上限には手動CUA用の8.9秒captureが合わず、その検証は成功扱いしない。CUAの実表示/操作の受入と区別する。

最終native検査で自身のmanaged hookを他Islandと誤判定する診断を発見し0a9715eで修正。bundle helperとは別に自身の正規managed commandを除外する1行修正。StrayIslandHookTests7件PASSで、本物のforeign hookと他ユーザーフックの保持、設定ファイルの非変更も検証。旧managedpathは正常なインストール先であり、重複していると推測してユーザーフックを削除しない。

既存hookの親タイトルが内部指示名のままになるnative不具合をc9ace44で修正。正確なPaseo親bindingのtitleだけを採用し、子の回答先/質問UUID/親応答状態を維持、回答後も正規title保持。PaseoForwardedQuestionTests5件PASS（追加1件含む）。

6e3ed6fでCodex正式source.subagent.thread_spawn.parent_thread_idを検証して保存/復元し、ローカル子の通常実行・完了・許可待ちも同じ可視集合から除外。親が正確に一致・live attachedのときのみ適用し、本人questionPrompt/waitingForAnswerと孤立した子は残して質問元/親名を補助表示。Core2/App3の追加テストを含め全体再実行PASS。内容/名前/作業ディレクトリによる子判定はしない。

66e7166では親子集合を各キュー操作で1回評価しO(n²)の再走査を避けた。状態キャッシュ追加なし。最終focused Core7/App8 PASS（`/tmp/mitama-island-1005-final-focused.log`）。

最終起動で次の根本原因を見つけ、e96a9c5/6f7f385/8a0bc27で修正した。SDK受信はCLI bridge startの成功に依存しない。早いSDK質問を後から来たCodex起動cacheがstate全置換で消していたため既存mergeへ統一し、live attentionはstale cacheまたは非attention scanで解消しない。同じSDKrequestは再通知されないので、再ポーリングに頼って紛失を隠さない。SDK先受信→cache→新しいtimestampのattached scan→同request poll→正確な子への回答を回帰検証。

テストがglobal registryを保存する問題はproduction保存元を変えず、AppModel/4storeの依存注入と全AppModelテストの共通temp factoryで修正。全テストの前後でproduction registry4ファイルがバイト単位で一致。混入した既知のテストID parent-native/child-nativeだけをローカルbackup付きで除去し、その他の記録は保持。テストのGhostty dedup条件は実ユーザーのhideIdle設定に偶然依存していたため2fc2b9fで試験条件を明示、既存assertは保持。

3260405で、親自身のpending0を理由に親カードへ投影中の子質問を消す最後の同期不具合を修正。正確な親子mappingと現questionUUID一致時のみ解消を防ぎ、直接親自身のstale要求解消は維持。SDK先受信→親pending0/子pending1同期→質問保持→子への回答の回帰PASS。通常起動1303の実Paseo SDK質問が保持され、親の一行へ表示されることをCUA確認。

8805637で、全3row/通知の共有headlineへexact known Paseo binding titleを渡し、自動命名が内部初期promptを再採用しないようにした。unknown/Paseo仮名/ローカル自動名は従来通り。転送質問の親rowmodeは親binding自身のラベルに統一し、子ClaudeBypassを親CodexFullAccessと誤表示しない。送信/エラーroutingは子の現SDKrequestのまま。Grok最終実証blockerと親子mode回帰を含む。

64e99dbで、Paseoの独自プロバイダ（`auto` など）を `agents.providers.<id>.extends` から読むよう修正（旧実装は存在しない `providers.custom` を読んでいた）。常用版でnative再確認: `auto` プロバイダの子がAskUserQuestionを出すと、親行に親のPaseo会話名、「子からの質問」に子のPaseo会話名、モードに「Claude Code · Bypass」と表示。島で選択→回答し、子が `ISLAND_ALIAS_TITLE_TEST_OK` を返したことを `paseo logs` で照合。テスト子は確認後にarchive。
