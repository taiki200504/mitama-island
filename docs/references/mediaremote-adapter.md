# MediaRemoteAdapter（再生中の曲の取得）

macOS 15.4 以降、アプリが直接 `MediaRemote.framework` を読み込んでも再生中の曲の情報が取れなくなった
（`com.apple.` で始まるバンドル ID を持つプロセスだけがこのフレームワークへのアクセスを許されるようになったため）。
Now Playing 機能は [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)（BSD-3-Clause）
というオープンソースの回避策を使ってこれを取得する。boring.notch や mew-notch など、同じ制約を抱える他の
notch アプリも同じライブラリを使っている。

## なぜ Perl 経由なのか

`/usr/bin/perl` は macOS 側から `com.apple.perl` というバンドル ID を与えられている数少ないシステムバイナリの
一つで、これが `MediaRemote.framework` へのアクセスを許可されている。mediaremote-adapter は

1. `mediaremote-adapter.pl`（Perl スクリプト、このアプリにそのままコミット済み）を
2. `MediaRemoteAdapter.framework`（Objective-C 製の薄いラッパー、ビルド生成物なので**コミットしない**）
   を渡して子プロセスとして起動する

という構成で、この Perl プロセスの中からフレームワークを読み込むことでアクセス制限を回避する。
`MediaRemoteAdapterProcess`（`Sources/OpenIslandApp/NowPlaying/MediaRemoteAdapterProcess.swift`）が
この子プロセスの起動・NDJSON 行の読み取り・再起動を担当する。

## フレームワークはビルド生成物であって配布物ではない

upstream は GitHub Releases にビルド済みバイナリを一切公開していない
（`gh release view` で確認済み、2026-09 時点）。フレームワークは CMake で自前ビルドする前提の配布形態になっている。

そのため、他の資産（フォントなど）のように「リリースアセットの SHA256 を固定してダウンロードする」ことができない。
代わりに以下の方式で完全性を担保している。

- `scripts/fetch-mediaremote-adapter.sh` が upstream の **特定コミット**（タグではなくコミット SHA）を pin する
- そのコミットの GitHub ソースアーカイブ（tarball）の **SHA256 をスクリプトにハードコード**しており、
  ダウンロード直後に照合して不一致なら即座に失敗する
- 検証済みのソースを `vendor/mediaremote-adapter/src/` に展開し、そこで `cmake` ビルドして
  `vendor/mediaremote-adapter/build/MediaRemoteAdapter.framework` を生成する
- `vendor/` は `.gitignore` 済み — フレームワークのバイナリはリポジトリに一切コミットしない

現在の pin: `v0.7.7`（コミット `e3ff5021eb0875858bd05f48d2e9ba2e962d1cf6`）。
upstream の新しいリリースを取り込むときは、`scripts/fetch-mediaremote-adapter.sh` 内の
`PINNED_TAG` / `PINNED_COMMIT` / `PINNED_SHA256` の3つを同時に更新する。

## 使い方

```
zsh scripts/fetch-mediaremote-adapter.sh
```

ローカルでフレームワークを手元に置いてから `swift run` すると、
`MediaRemoteAdapterProcess` が `OPEN_ISLAND_MEDIAREMOTE_FRAMEWORK` 環境変数
→ アプリバンドル内 `Contents/Frameworks/MediaRemoteAdapter.framework`
→ リポジトリ直下の `vendor/mediaremote-adapter/build/MediaRemoteAdapter.framework`
の順で探しに行く。`scripts/package-app.sh` / `scripts/package-mitama-island.sh` は、
このフレームワークが存在すれば署名済みアプリの `Contents/Frameworks/` にコピー・コード署名し、
存在しなければ警告を出して静かにスキップする（CI はこのスクリプトを実行しないため、
CI 上のパッケージ検証はフレームワークなしのパスを常に通る）。

## コマンド

Perl スクリプトへ渡す主なサブコマンド（詳細は upstream README）。

| コマンド | 用途 |
|---|---|
| `stream` | 再生中情報を NDJSON で継続的に流す。既定で差分（`diff: true`）配信 |
| `get` | 一度だけ取得 |
| `send <ID>` | 再生 / 一時停止 / スキップなどの MediaRemote コマンドを送る |
| `seek <MICROS>` | 再生位置をマイクロ秒単位で移動する |
| `test` | アダプタが今も機能しているかを確認する（将来の macOS で壊れた場合の検知用） |

## ライセンス

mediaremote-adapter 本体は BSD-3-Clause。このリポジトリは GPLv3 なので互換性に問題はない。
`Sources/OpenIslandApp/Resources/MediaRemoteAdapter/LICENSE` に原文をそのまま同梱している。
