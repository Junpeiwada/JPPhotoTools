# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

JPPhotoTools は、撮影後の写真ワークフローを一本化する **macOS 統合デスクトップアプリ**。これまで個別に作ってきた写真ツール群を、タブで機能を切り替える 1 つのアプリに集約する。撮影後の処理を時系列順に 4 タブで並べる:

| タブ | 機能 | 由来アプリ | Core |
|------|------|-----------|------|
| 取り込み・整理 | RAW/JPG ペアの仕分け、孤立 RAW の退避 | RAW-Trash | RawTrashCore |
| ジオタグ | GPX・地図・マッチングで GPS/日時タグを書き込み | GeoTagger | GeoTaggerCore |
| HEIC 変換 | ゲインマップ付き HEIC の生成（HDR 生転写・SDR→HDR 合成） | GainForge | GainForgeCore |
| リサイズ書き出し | 共有用に高品質 JPEG リサイズ | JpegResizer | JpegResizerCore |

要環境: macOS 15 以降（Apple Silicon）、Swift 6 / Xcode 16 以降。GeoTagger タブの GPS/日時書き込みのみ外部の [exiftool](https://exiftool.org/) をサブプロセスとして呼ぶ（`brew install exiftool`。同梱しない）。

## アーキテクチャ（モジュール分離 + XcodeGen）

各由来アプリの「Core（変換ロジック・UI 非依存）／ App（SwiftUI）」3 層構成を踏襲しつつ、**4 つの独立アプリを 1 つの統合シェルに合流させる**。ここが本リポジトリ固有の勘所で、依存の向きは常に `App → Packages → External`:

```
External/                vendored（upstream をコピー同梱した独立アプリ一式）
  GainForge/               GainForgeCore を含む（.package(path:) で参照）
  JpegResizer/             JpegResizerCore を含む
Packages/                  ローカル Swift Package 群
  GainForgeApp/            External/GainForge の Core をラップした「App 層」モジュール
  JpegResizerApp/          External/JpegResizer の Core をラップした「App 層」モジュール
  RawTrashCore/            仕分け系 Core（App 層を挟まず統合アプリが直接使う）
  GeoTaggerCore/           GPX・地図・マッチング系 Core（同上）
  PhotoKitShared/          共通土台（AppViewModel / FeatureShell / OutputPlanner / ImageProbe など）
App/                       統合アプリ本体（XcodeGen 管理の Xcode プロジェクト）
  Sources/                 ContentView（タブ器）・JPPhotoToolsApp・Updater・GeoTagger タブ実装 ほか
  project.yml              ★真実のソース（ターゲット・依存・Info.plist を定義）
```

### なぜ 2 系統（App 層モジュール / Core 直接）に分かれるか

- **HEIC 変換・リサイズ書き出し** は「ドロップ受け入れ → バッチ並列変換 → 進捗テーブル」という共通パイプラインを持つ。この共通 App シェル（`PhotoKitShared` の `FeatureShell` / `AppViewModel` 相当）に乗せられるため、由来アプリの App 層を `GainForgeApp` / `JpegResizerApp` として独立ライブラリ化して差し込む。タブは「変換関数・設定 UI・テーブル列定義」だけを差し替える。
- **取り込み・整理（RAW-Trash）・ジオタグ（GeoTagger）** は仕分け／地図マッチングという独自パイプラインで共通シェルに乗らない。よって App 層を作らず、統合アプリ内の専用タブ（`RawTrashTab` / `App/Sources/GeoTagger/GeoTaggerTab`）が Core を直接使う。

### モジュール境界で名前衝突を解消する

GainForge と JpegResizer は両方とも `AppViewModel` / `FileItem` などの**同名型**を持つ。これを別モジュール（`GainForgeApp` / `JpegResizerApp`）に閉じ込めることで名前空間を分けて共存させている。統合アプリ（`App/Sources`）からは App 層モジュールの公開 API だけを見ればよく、内部の Core（`GainForgeCore` の Bundle.module 経由 ML-LUT など）はパッケージ参照のまま保たれる。

### External はコピー同梱（vendored）

`External/GainForge` `External/JpegResizer` は upstream リポジトリを**コピーして取り込んだもの**。upstream 側の変換ロジック（生転写の落とし穴・SDR→HDR 合成など）を触る必要が出たら、まず各 `External/*/CLAUDE.md` を読むこと（詳細な移植知見がそちらにある）。

## Sparkle 自動更新

[App/Sources/Updater.swift](App/Sources/Updater.swift) の `UpdaterController` が Sparkle をラップ（アプリ全体で 1 つ、`@StateObject`）。更新フィード（appcast）と署名検証鍵は Info.plist の `SUFeedURL` / `SUPublicEDKey` から読む。これらは `project.yml` の `info.properties` で定義し、XcodeGen が実 Info.plist を生成する（Sparkle の任意キーは `INFOPLIST_KEY_*` では注入できないため）。appcast は GitHub Pages（`https://junpeiwada.github.io/JPPhotoTools/appcast.xml`）でホストし、[.github/workflows/release.yml](.github/workflows/release.yml) がタグ push で署名・公証・appcast 生成・Pages 公開まで自動化する。リリースは **タグ push** で発火する（`git tag v1.2.0 && git push origin v1.2.0`）。バージョン更新→コミット→タグ push を 1 コマンドで行うヘルパ [Tools/release.sh](Tools/release.sh) も同梱（`Tools/release.sh 1.2.0`、または VSCode の NPM SCRIPTS / `npm run release -- 1.2.0`。ルート [package.json](package.json) は本アプリのビルドには無関係で、この開発補助スクリプトのためだけに置いている）。手順詳細は [Docs/リリース手順.md](Docs/リリース手順.md)。

## コマンド

### GUI（Xcode）

```sh
open App/JPPhotoTools.xcodeproj        # Xcode で JPPhotoTools スキームを Run
```

### XcodeGen（重要）

`App/JPPhotoTools.xcodeproj` は **XcodeGen 管理** で、[App/project.yml](App/project.yml) が真実のソース。ターゲット・ビルド設定・依存・Info.plist（Sparkle キー含む）を変える場合は **`project.yml` を編集して再生成**する。`.xcodeproj` を直接編集しても次回再生成で失われる:

```sh
cd App && xcodegen generate
```

`App/Sources/` 配下にファイルを追加したら **`cd App && xcodegen generate` が必要**。`sources` は個別ファイル列挙方式（`type` 省略のデフォルト）を使っており、pbxproj に各ファイルが列挙される。追加後に再生成しないと `Cannot find 'X' in scope` になる。設定変更時も必ず `project.yml` 側で行う。

**`type: syncedFolder`（Xcode 16 フォルダ参照）は使わないこと。** 再生成不要になる利点はあるが、XcodeGen が生成する pbxproj に `Resources` ビルドフェーズが作られず、`Sources/Assets.xcassets` がコンパイルされない（`.car` がバンドルに入らず、`No color named '...' found in asset catalog` 警告と共に色・文字・ボタンが表示破綻する）。`type: folder` も同様にソース扱いされず不可。

### テスト（各パッケージ / SwiftPM）

ロジックテストは Core パッケージ側にある（`RawTrashCore` / `GeoTaggerCore` / `PhotoKitShared` ほか）。各パッケージディレクトリで `swift test`:

```sh
cd Packages/GeoTaggerCore && swift test
cd Packages/RawTrashCore  && swift test
cd Packages/PhotoKitShared && swift test
```

### ドキュメントの目次生成

```sh
python3 Tools/GenDocsToc/gen_toc.py Docs/アプリ概要.md   # 「# タイトル」直後に「## 目次」を生成・更新（冪等・依存なし）
```

## ドキュメント

- アプリ概要・設計: [Docs/アプリ概要.md](Docs/アプリ概要.md)
- 実装計画: [Docs/実装計画.md](Docs/実装計画.md)
- GeoTagger 統合: [Docs/GeoTagger統合.md](Docs/GeoTagger統合.md)
- リリース手順: [Docs/リリース手順.md](Docs/リリース手順.md)
- 各由来アプリの詳細知見: `External/GainForge/CLAUDE.md` / `External/JpegResizer/CLAUDE.md`
