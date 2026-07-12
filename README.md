# JPPhotoTools

撮影後の写真ワークフローを一本化する macOS 統合デスクトップアプリ。
これまで個別に作ってきた写真ツール群を、タブで機能を切り替える1つのアプリに集約する。

現在の統合対象:

| タブ | 機能 | 由来アプリ |
|------|------|-----------|
| 取り込み・整理 | RAW/JPG ペアの仕分け、孤立 RAW の退避 | RAW-Trash |
| HDR 変換 | ゲインマップ付き HEIC の生成 | GainForge |
| リサイズ書き出し | 共有用に高品質 JPEG リサイズ | JpegResizer |

## 設計

「Core（変換ロジック・UI 非依存）／ CLI ／ App（SwiftUI）」の3層構成を踏襲し、
機能ごとの `XxxCore` を Swift Package として横並びに配置。ドロップ受け入れ・
バッチ並列変換・進捗表示などの共通 App シェルは1つに集約し、タブは
「変換関数・設定 UI・テーブル列定義」だけを差し替える。

詳細は [Docs/アプリ概要.md](Docs/アプリ概要.md) を参照。

## ドキュメントの目次生成

`Docs/` 配下の Markdown に目次を付ける／更新するには、同梱の目次生成ツールを使う（Python 標準ライブラリのみ・依存なし）。

```bash
python3 Tools/GenDocsToc/gen_toc.py Docs/アプリ概要.md   # 「# タイトル」直後に「## 目次」を生成・更新（冪等）
```

詳細は [Tools/GenDocsToc/README.md](Tools/GenDocsToc/README.md) を参照。

## 動作環境

- macOS 15 以降（Apple Silicon）
- Swift 6 / Xcode 16 以降

### exiftool（GeoTagger タブで必須）

GeoTagger タブの GPS／日時タグ書き込みは [exiftool](https://exiftool.org/) をサブプロセスとして呼び出す。
アプリには同梱していないため、別途インストールが必要（`/opt/homebrew/bin` / `/usr/local/bin` / `/usr/bin` を探索する）。

```bash
brew install exiftool
```

未インストールの場合、他タブ（取り込み・整理／HDR 変換／リサイズ書き出し）は動作するが、GeoTagger の書き込みはエラーになる。

## ビルド / 実行

Xcode プロジェクトは [App/](App/) 配下にある（`App/JPPhotoTools.xcodeproj`）。

```sh
open App/JPPhotoTools.xcodeproj
# Xcode で JPPhotoTools スキームを Run

# プロジェクトファイルは XcodeGen 管理（App/project.yml が真実のソース）。
# ターゲット・依存・Info.plist 設定を変えたら再生成する:
cd App && xcodegen generate
```

## テスト

ロジックのユニットテストは各 Core パッケージ側にある（SwiftPM）。パッケージディレクトリで `swift test`:

```sh
cd Packages/GeoTaggerCore && swift test
cd Packages/RawTrashCore  && swift test
cd Packages/PhotoKitShared && swift test
```

## ダウンロード

[Releases](https://github.com/Junpeiwada/JPPhotoTools/releases) から最新版の `.app`（zip）を入手できる。
アプリ内に自動更新（Sparkle）を備えており、新しいリリースを検出すると通知する。

## ライセンス

MIT — 詳細は [LICENSE](LICENSE) を参照。
