# Task1121 Island 共通アクセント独立review

- 対象: `.worktrees/island-brand-ribbon-1121`（基準 `bfee40c9`）。Read と単純な `git diff`・grep のみ。Git 変更・テスト・build・アプリ起動・追加委譲なし。元 repo `mitama-island` は未変更。
- 読んだ物: `island-accent-impl.md`、`island-accent-contrast.json`、実 diff（`Theme/IslandTheme.swift`・`Views/Island/IslandCompletionActionView.swift`・`Views/SettingsView.swift`・`Assets/Brand/README.md`）、`accent` の全参照箇所（`Sources` 全体の grep）と主要な呼び出し元（`IslandButtonStyles`・`IslandLivePreview`・`ConversationSurfaceView`・`IslandOpenedContentView`・`IslandShelfViews`・`StructuredQuestionPromptView`・`IslandPanelView`・`IslandDesignPalette`・`SettingsView` の tint/borderedProminent）。
- 区分: 【実測】読んで確認 / 【未検証】。Swift の parse・build・test・実 UI は未確認（親が実行中・実 UI 合格とは言わない）。

## 結論
**P1 なし。P2 が 1 件（実画面で要確認の可能性）。** 変更は色の定義とその直接の補正 3 箇所だけで、意味色・agent 色・音・形状・機能は不変。親の静的計算（5.61〜10.53）は定義色から再現でき、補正が必要な「ラベンダー塗り＋白文字」の組合せのうち、**`SettingsView:788` の `.borderedProminent` ボタンだけが補正の対象から漏れている可能性**がある。

## 差分の確認【実測】
| 変更 | 内容 |
|---|---|
| `IslandTheme.swift` | `accent`: `SAOGrammar.Palette.accentOrange`（`#FF7A00`）→ `Color(hex: 0xC8B6FF)`。`accentOnLight = Color(hex: 0x493797)` を追加。`ink/paper/statusTints/glowRadius/animationProfile/soundProfile/shape` は不変 |
| `IslandCompletionActionView.swift` | 白い完了カードの Markdown リンクだけ `accent` → `accentOnLight`（`#493797` on 白＝9.22:1）。他の `accent` 使用なし |
| `SettingsView.swift` | `remoteSetupStep` の番号文字と `UpdateBanner` の文字・アイコンを `V6Palette.paper` → `V6Palette.ink`。塗り（`selection`＝`accent`、番号は 70% 不透明）・サイズ・形状・影・動作は不変 |
| `Assets/Brand/README.md` | 「In-app accent」節を追記。意味色の橙・agent 色・状態色は役割を維持、UI は未検証と明記 |

## `accent` の全 caller と背景の対【実測】
`IslandThemes.current.accent`／`theme.accent`／`IslandDesignPalette.selection`（＝`accent` の別名）の使用箇所を全て追い、前景・背景の対を確認。**Island のパネルと設定ウィンドウは濃色**（`ink #06101E`、設定は `.preferredColorScheme(.dark)`）。

| 使い方 | 箇所 | 判定 |
|---|---|---|
| 濃背景上の文字・アイコン・線・影（ラベンダーは `#06101E` に対し約 10.5:1） | `ConversationSurfaceView`（話者名・展開ボタン・枠）、`IslandOpenedContentView` 通知バー、`IslandShelfViews`（アイコン・破線）、`OnboardingView`、`IslandBootSplashView` のリング、`StructuredQuestionPromptView:157` 選択アイコン、`LinkstartView` の影、`IslandPanelView` のホバー光、`SettingsRow/IconChip/ThemeGround` の薄い塗り・枠 | OK（コントラスト十分、または装飾） |
| 塗り＋**濃い文字** | `IslandButtonStyles:68,73`（決定カードの primary は文字 `ink`・背景 `accent`）、`IslandLivePreview:132-133`（選択チップは文字 `ink`・塗り `accent`） | OK（10.53:1。文字色は元から `ink`） |
| 塗り＋文字を今回 `ink` に変更 | `UpdateBanner`、`remoteSetupStep`（70% ラベンダー塗りで 5.61:1） | OK（補正済み。塗りは `ink` 背景に重ねた概算） |
| 白カード上 | 完了カードのリンクのみ（`accentOnLight`） | OK |
| 半透明の塗り・枠（`accent.opacity(0.08–0.55)`） | `IslandButtonStyles:180,214,224,246,258`、`IslandOpenedContentView:205`、`IslandShelfViews:79,92` など | OK（背景は濃色、文字は paper/ink 側が担う） |
| SwiftUI の `.tint(accent)` | `SettingsView:39`（ウィンドウ全体）、`SettingsPane:43` | **下記 P2** |
| lightCard の primary ボタン | `IslandButtonStyles:114-115` は `SAOGrammar.selectionGradient`（橙→琥珀）で、`accent` ではない。文字は `ink` | 影響なし（橙のまま） |

## P2（要確認）: `.tint(accent)` 下の `.borderedProminent` ボタン
- `SettingsView.swift:788` の「修復」ボタンは `.buttonStyle(.borderedProminent)`。ウィンドウ全体が `.tint(IslandThemes.current.accent)`（L39）なので、塗りが**ラベンダー `#C8B6FF`** になる。`borderedProminent` のラベルは既定で白に近い色になるため、**白文字＋ラベンダー塗りで約 1.6:1** となる可能性がある（旧アクセント橙でも白文字は約 2.8:1 で弱かったが、さらに悪化）。macOS が淡い tint でラベル色を自動で暗くするかは、私は確認していない【未検証】。
- 今回の補正（`UpdateBanner`/`remoteSetupStep`）にこのボタンは含まれていない。実画面で確認し、読みにくければ「修復」ボタンのラベルに `.foregroundStyle(V6Palette.ink)` を付ける（または `.tint` をそのボタンだけ濃色にする）。
- 同じ `tint` の下の `Toggle`・`Picker`・`Slider`・選択行は、濃背景上のラベンダー塗り＋白のつまみ等で、通常は読み取り可能（実画面は未確認）。

## 不変の確認【実測】
- **意味色・agent 色**: `statusTints`（running=シアン、approval=黄、answer=`#FFD35A`、completed=ライム、aggregate=琥珀、critical=赤）は diff に出ない。`SAOGrammar.Palette.accentOrange` を直接使う約 30 箇所（ヘッダの要素、提案ボタン、タイマー、セッション行、NowPlaying など）も不変＝**橙の「注意」意味は維持**。
- **音・形状・動作**: `soundProfile`・`animationProfile`・`shape`・`glowRadius`・ボタン/カードの寸法に変更なし。機能コードの変更なし。
- **テスト**: `Tests` で `accent` を参照するのは `SAOPeekGaugeTests` の `accentOrange` 比較のみ（`SAOGrammar.Palette.accentOrange` を直接参照しており影響なし）。`IslandThemeTests`/`SettingsThemeTests` に `theme.accent` の断定は無い【grep 実測】。

## P3
1. **橙とラベンダーの混在**: 共通 `accent` はラベンダーになったが、lightCard の primary ボタン（`selectionGradient`）、ヘッダ・提案ボタン・タイマー等の直接 `accentOrange` 参照は橙のまま。意味色としての橙は意図的だが、「アプリの声」としての色が 2 系統に見える可能性。
2. **`UpdateBanner` の影が `.blue`**（`SettingsView:1207`、既存）でラベンダーとずれる。
3. **コメントの陳腐化**: `IslandTheme.swift:68` の「icy paper and orange give the panel its edge」は旧アクセント前提の説明。
4. 計算値は「定義色の静的計算」（`island-accent-contrast.json` の `nativeUIVerified: false`）。半透明の重なり・ブラー・システムの描画補正は含まない。
5. `accentOnLight` は現状 1 箇所でのみ使用（過剰実装ではない）。

## 再review（P2 の修正後、`SettingsView.swift:784-792` と検証 JSON を Read）【実測】
- **修正内容**: 修復ボタンが `Button(label) { … }` から `Button { model.repairHooks() } label: { Text(lang.t("setup.diagnostics.repair")).foregroundStyle(V6Palette.ink) }` に変わり、ラベル文字だけが `ink`（`#06101E`）になった。`.buttonStyle(.borderedProminent)`・表示条件（`hasRepairableIssues`）・アクション（`model.repairHooks()`）・文言キーは不変。`Sources` 全体で `.borderedProminent` を使う箇所は**この 1 箇所のみ**（grep 実測）で、他に同種の漏れはない。
- **判定**: **P2 解消**（コード上）。ラベルの内側の `foregroundStyle` はスタイルが与える既定色より優先されるため、ラベンダー塗り `#C8B6FF`＋`ink` 文字（定義色で約 10.5:1）になる想定。ただし **SwiftUI が実際にラベル色をこの指定で上書きするか、無効状態の見え方**は実画面でないと確認できない【未検証】。
- **検証記録**（`island-accent-verification.json`）: base `bfee40c9`、`swiftParse` は IslandTheme/IslandCompletionActionView/SettingsView の 3 ファイルで exit 0（`swiftc -frontend -parse`、**構文のみ**）、`diffCheck: true`、`fullTypecheck: false`、`swiftTests: false`、`nativeUI: false`、`jev: false`、`ready_for_prod: false`。型検査・テスト・実 UI は未実施。
- **残る P3 は変更なし**（橙とラベンダーの混在、`UpdateBanner` の影が `.blue`、旧コメント、静的計算の限界）。

## 未検証
Swift parse／build／テスト実行（親が実行中）／実画面（Island の開閉・会話・棚・完了カード・設定ウィンドウ）／`.borderedProminent` ボタンの実際のラベル色／`.tint` 下のコントロール全般の見え方／Dock・通知・Linkstart・起動画面での実描画／アクセシビリティ（VoiceOver・高コントラスト設定）。**実 UI 合格とは言えない**（draft 143 向け）。
