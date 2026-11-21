# Task1121 Island アプリアイコン（asset-only）独立review

- 対象: `.worktrees/island-brand-ribbon-1121`（base `ad33cbbe`、branch `feat/brand-ribbon-icon-1121`）。Read と単純な `git status/diff/show`・grep のみ。実アプリ起動・Git 変更・Swift build・test・追加委譲なし。元 repo `mitama-island`（DMG 2 枚が dirty）は読むだけで未変更。
- 読んだ物: `island-icon-impl.md`、`island-icon-verification.json`、`island-verify.py`、`island-protected-dmg.json`、worktree の `Assets/Brand/README.md`（新旧）、`scripts/{generate_brand_icons.py, package-app.sh, launch-dev-app.sh, generate-v6-appicon.swift}`・`.github/workflows/release.yml` の該当行。
- 区分: 【実測】読んで確認 / 【未検証】。実 Dock・Finder・署名・DMG・新アイコンでの起動は未検証（draft のみ）。

## 結論（初版。**P1 は下の「再review」で解消確認済み**）
**初版では P1 が 1 件ありました（アイコンが実際には出荷されない）。** 資産自体（20 PNG・ICNS・README）は承認原画から正しく作られ、変更範囲も保護範囲を守っているが、**既存のパッケージ手順が起動のたびに旧 Bar+Dot アイコンを再生成して上書きする**ため、このままではビルド成果物に新アイコンが入らない。

## P1: パッケージ/開発起動の手順が Ribbon アセットを旧ロゴで上書きする
- `scripts/package-app.sh:43` と `scripts/launch-dev-app.sh:31` は、`OpenIsland.icns` を bundle へコピーする**直前に無条件で** `python3 scripts/generate_brand_icons.py` を実行する【実測】。
- 同 script の `main()`（L53-65）は `AppIcon.appiconset/` と `OpenIsland.iconset/` を **`ensure_clean_dir` で削除して作り直し**、`write_app_icons()`（L291-309）は `Assets/Brand/app-icon-v6.png`（旧 Bar+Dot マスター）だけを元に全スロットを再生成（内容比 824/1024 の余白付き・LANCZOS 縮小）、`Contents.json` を書き直し、`build_icns()` で `OpenIsland.icns` を再生成する【実測】。
- 結果: **Dev アプリの起動（`launch-dev-app.sh`）も、リリースの DMG 作成（`package-app.sh`、`release.yml` から使われる経路）も、毎回 Ribbon の 20 PNG と ICNS を破棄して旧ロゴに戻す**。作業ツリーも Ribbon 差分が旧ロゴ差分に変わって dirty になる。`README.md` の「旧ジェネレータ実行後は手順で復元する」という注意書きは、**スクリプトが自動で走る**以上、運用でも CI でも守られない。
- 対処案（いずれも「資産だけ」の範囲を超えるため親/本人判断）: (a) `package-app.sh`/`launch-dev-app.sh` から app icon 再生成を外す、または `generate_brand_icons.py` に app icon 生成を飛ばす分岐を追加、(b) 暫定として `Assets/Brand/app-icon-v6.png`（ジェネレータの唯一のマスター）を Ribbon 原画に差し替える（ただしジェネレータは 824/1024 の余白を足して再縮小するため、現在の「Browser と同一の派生」とは見た目・バイトが変わる）。**このままマージしても、出荷物のアイコンは変わらない。**

## 確認できた点【実測】
| 観点 | 結果 |
|---|---|
| 変更ファイル | `git status`: `AppIcon.appiconset` の PNG 10、`OpenIsland.iconset` の PNG 10、`OpenIsland.icns`、`Assets/Brand/README.md` の **計 22**（impl の「21 binary＋README」と一致）。`Contents.json`・Swift・署名・DMG 資産・`Internal/`（Scout）・`Source/`・`app-icon-v6.png`・scripts は無変更 |
| 寸法・SHA | 検証 JSON: 20 PNG すべて `Contents.json` の size×scale に一致する正方形（16/32/32/64/128/256/256/512/512/1024）。`island-verify.py` が各 PNG を **Browser の承認済み 10 PNG とバイト同一**であることを assert。impl 記載の 10 SHA は、前便の Browser 実装記録の SHA と全一致。`git diff --stat` のバイト数（例: 512@2x=980,513、512=256,759、32@2x=5,826）も Browser/Hub の同スロットと一致 |
| 既存 Contents の維持 | `Contents.json`（asset catalog のメタデータ）は未変更で、ファイル名と寸法は従来どおり |
| ICNS | `icns` マジックと全長ヘッダ一致、1,659,454 B。**逆展開で 8 スロットはバイト一致、16×16 と 32×32 はバイト不一致**（iconutil が小サイズを再エンコードする挙動と思われる）。**親の `magick compare` でも 16/32 に小さい非 0 差**が出ており、デコード後ピクセルの完全一致は**主張できない**。差の程度は親が記録中【未検証】 |
| 保護資産 | `island-verify.py` が元 repo の `dmg-background.png`/`@2x.png` の SHA-256 を事前記録値と照合し `protectedDmgUnchanged: true`（元 repo の dirty は別セッションのもので、本作業は触れていない）。内部 Scout アセットも diff に出ていない |
| 起動/Dock | `appLaunch/swiftBuild/dockVerified` すべて false＝未実施 |

## P3
1. **README の復元手順は Browser 側 repo のパスに依存**（`browser_iconset=/absolute/path/to/mitama-os/...`）。Island は独立 repo のため、他 repo の資産へ依存した再生成手順になる。原画 SHA（`1ec0ee…`）は明記済みで検証可能。
2. **旧 README の説明が消えた**: 旧版にあった Scout ジェネレータの出力一覧（`Internal/color|template|badge` など）と「Scout 由来」の記述が新 README では要約に縮約。`Internal/` の再生成手順の正本は `generate_brand_icons.py` 側に残るが、文書としての網羅は減った。
3. **同一アイコンの重複**: mitama Browser・Glasses・Island が同じ Ribbon（light）アイコンになる。Dock/Cmd-Tab で Browser と Island を見分けにくくなる可能性（ブランド統一の意図どおりだが、識別性は実 Dock で要確認）。
4. **見た目の余白**: 承認原画は 1254px の角丸ガラスタイルが余白を持って描かれ、旧ジェネレータの 824/1024 規則とは別。Dock での大きさ・余白は【未検証】。
5. **検証 JSON の出所**: `icnsRoundTrip`・`icnsSha256` は `island-verify.py` の出力項目に無く、追補の検証で追記されたものと見られる（再現手順が script に無い）。

## 判定
**P1 あり（上記のスクリプト自動再生成）。** 資産の中身・範囲・保護は問題なし。出荷物に反映するには、再生成手順の扱い（スクリプトのガード、またはマスター差し替え）を決めたうえで、実 Dock・署名・DMG を検証する必要がある。

## 再review（P1 修正後の最終差分を Read／`git diff`）【実測】
| 観点 | 結果 |
|---|---|
| 変更ファイル | `git status`: 既存の PNG 20・`OpenIsland.icns`・`README.md` に加え **`scripts/package-app.sh`・`scripts/launch-dev-app.sh` の 2 つ**のみ。Swift・署名設定・DMG 資産・`Contents.json`・`Internal/` は無変更 |
| 自動の旧ジェネレータ呼出し | **除去**。両 script から `python3 "$brand_script"` と `brand_script=` の定義を削除（以前の grep で `brand_script` の出現は定義と呼出しの 2 箇所のみ＝参照の取り残しなし）。リポ内で `generate_brand_icons` に触れるのは `scripts/generate-v6-appicon.swift` のコメントだけで、**自動で走る呼出し元は残っていない** |
| ICNS ガード | `[[ ! -f "$brand_icon" \|\| ! -s "$brand_icon" ]]` で存在・非空を検査し、満たさなければ stderr に `ERROR: missing or empty app icon ICNS` を出して `exit 1`。**`swift build` より前**（launch は冒頭の `repo_root`/`brand_icon` 直後、package は変数定義直後）に置かれ、不備を早期に止める |
| コピー経路 | `cp "$brand_icon" "$bundle_dir/Contents/Resources/OpenIsland.icns"` は両 script とも**変更なし**（diff に出ない）。コピー元はコミット済み ICNS そのもの |
| 署名・DMG 生成 | `generate_dmg_background.py`・署名・公証・DMG 作成の記述は diff に無く**不変**。`release.yml:115` の `Contents/Resources/OpenIsland.icns` 検査も変更なし |
| README | 「コミット済み `OpenIsland.icns` が packaging/開発起動の正本。両 script は存在・非空だけ検査してそのままコピーする。承認原画が変わったら手順で手動再生成する」と更新（L24）。再生成手順（Browser の承認 PNG を `cp` → `iconutil`）と原画 SHA は維持。旧ジェネレータの注意書きも残存 |

### ガードの動作確認（`island-icon-guard-results.json` を Read）
`scope`: 「Extracted ICNS preflight only; no launch/build/package/sign/install code executed」。**ガード部分だけを抜き出して実行した 6 ケース**: `package-app.sh`／`launch-dev-app.sh` × {valid, missing, empty} ＝ **valid は exit 0、missing と empty は exit 1**（6/6 が期待どおり）。親の報告では bash・zsh の両方で確認。スクリプト本体・Swift・署名・アプリ起動は実行していないので、**スクリプト全体の動作は未検証**。

### P1 の判定
**解消。** 毎回の起動・パッケージ作成で Ribbon の PNG/ICNS が旧 Bar+Dot に上書きされる経路は無くなり、出荷物はコミット済み ICNS を使う。親の `bash -n`/`zsh -n`/diff チェック通過は親報告として受領（私は script を実行していない）。

### 再review で残る点（P3）
- 旧ジェネレータ `generate_brand_icons.py` 自体は残っており、**手動で実行すれば Ribbon を旧ロゴで上書きする**（README に復元手順の注意あり）。誤実行防止のガード（スクリプト側）は未追加。
- ICNS の 16×16・32×32 はデコード差が小さく非 0（iconutil の再エンコードによると見られる）。**デコード後ピクセルの完全一致は主張しない**（初版の注意を維持、差の程度は親が記録中）。
- 前掲の P3（README の他 repo 依存、旧 README の説明縮約、同一アイコンの識別性、余白）は変更なし。

## 未検証
実 Dock・Finder・Cmd-Tab での見え方／ICNS 16・32 のデコード差の程度（親が記録中）／署名・公証・DMG の作成／新アイコンでのアプリ起動・インストール／`release.yml` が `package-app.sh` を呼ぶ経路の実行確認（`release.yml:115` が `Contents/Resources/OpenIsland.icns` を検査する点までは確認）／`generate-v6-appicon.swift` が書き出す場所の詳細。
