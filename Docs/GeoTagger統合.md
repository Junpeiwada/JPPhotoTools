# GeoTagger 統合計画

GPX トラックログで写真（JPEG）にジオタグを付与する **GeoTagger**（Electron / TypeScript）を
Swift へ移植し、JPPhotoTools の 4 番目のタブとして統合する。機能は**そのまま移行**する
（UI 実装とライブラリは置き換えるが、ユーザーから見た挙動・ワークフローは維持する）。

全体方針は [アプリ概要.md](アプリ概要.md)、フェーズ進捗は [実装計画.md](実装計画.md) を参照。

## 変更履歴

- 2026-07-10: 初版。移植方針（ImageIO / MapKit / オフライン TZ 変換）を決定し、計画を策定。
- 2026-07-10: GT1〜GT3 一式（Core / タブ UI / 統合）を実装。実写真での検証で ImageIO
  書き込みが Sony 機 HDR の Gain Map（MPF 補助画像）を壊す問題が判明したため、
  `GpsWriter` を exiftool プロセス起動方式（`-overwrite_original`）へ書き換えた
  （§3.1 / §7 / §8 を実態に合わせて更新。exiftool は外部依存として復活）。
  `swift build` / `swift test`（62 件）警告ゼロで通過。`A1_07217.jpg` の複製で
  Gain Map（`MPImage2: Gain Map Image`）保持とファイルサイズ完全一致（無再圧縮）、
  GPS/DateTimeOriginal/Offset 系タグの反映を確認。
- 2026-07-10: 実データ（写真 2,196 枚 + GeoShutter GPX 61 ファイル、マージ後約135万点）で
  実運用検証したところ2件の問題を発見・修正した。
  1. **GPX パース/マージ/マッチングが `@MainActor` 上で同期実行されており、約2分間 UI が
     完全フリーズしていた**（実測）。`GeoTaggerViewModel.addGpxFiles` / `runPreview` を
     async 化し、`XMLParser` の同期パースは `DispatchQueue.global(qos: .utility)` へ
     `withCheckedContinuation` で逃がして実行するよう変更（Swift Concurrency の協調
     スレッドプールに直接乗せると、コア数固定のプールが専有され無関係な `MainActor` 処理まで
     数秒〜十数秒遅延することを実測で確認したため）。
  2. 上記フリーズの陰に隠れていたが、**写真の99.6%（2,188/2,196枚）が撮影時点で既に
     GPS Exif を持っており**、既定 `overwriteGps=false`（元 GeoTagger と同じ既定値）により
     仕様通り「— スキップ」判定になっていた。これは意図した挙動（§5.3）だが気づきにくいため、
     GpxSidebarView にスキップ件数と上書きトグルへの誘導メッセージを追加した（既定値自体は
     元アプリ踏襲のため変更していない）。

## 目次

- [1. スコープと決定事項](#1-スコープと決定事項)
- [2. 元アプリの機能インベントリ](#2-元アプリの機能インベントリ)
- [3. 技術置換の方針](#3-技術置換の方針)
  - [3.1 EXIF 読み書き: exiftool → ImageIO](#31-exif-読み書き-exiftool--imageio)
  - [3.2 地図: Leaflet/OSM → MapKit](#32-地図-leafletosm--mapkit)
  - [3.3 座標→タイムゾーン: geo-tz → オフライン Swift パッケージ](#33-座標タイムゾーン-geo-tz--オフライン-swift-パッケージ)
  - [3.4 その他の置換](#34-その他の置換)
- [4. アーキテクチャ](#4-アーキテクチャ)
- [5. 詳細設計](#5-詳細設計)
  - [5.1 GeoTaggerCore（ロジック層）](#51-geotaggercoreロジック層)
  - [5.2 タブ UI（App 層）](#52-タブ-uiapp-層)
  - [5.3 維持すべき細かい挙動（チェックリスト）](#53-維持すべき細かい挙動チェックリスト)
- [6. 作業ステップ（GT1〜GT3）](#6-作業ステップgt1gt3)
- [7. リスクと検証計画](#7-リスクと検証計画)
- [8. 完了条件](#8-完了条件)

---

## 1. スコープと決定事項

| 論点 | 決定 |
|------|------|
| 統合形態 | **1 タブに全機能を収める**（元アプリの1ウィンドウ構成をタブ内の分割ペインで再現。別ウィンドウは必須ではないため設けない） |
| タブ位置 | **末尾（4 番目）**。既存 3 タブ（整理 / HDR 変換 / リサイズ）の並びは変えない |
| EXIF 読み書き | **ImageIO ネイティブ**（exiftool 依存を持ち込まない） |
| 地図 | **MapKit**（SwiftUI `Map`。標準 / 衛星切替は `mapStyle` で実現） |
| 座標→タイムゾーン | **オフライン Swift パッケージ**（第一候補: SwiftTimeZoneLookup） |
| 機能スコープ | 元 GeoTagger の機能をそのまま移行（DateTimeOriginal / Offset 書き換えを含む）。Electron 固有機能（DevTools・CSP 等）のみ除外 |

## 2. 元アプリの機能インベントリ

元ソース（`/Users/junpeiwada/Documents/Project/GeoTagger`、実質約 1,400 行）の精読で確定した移植対象:

### 移植する機能

| # | 機能 | 元実装 |
|---|------|--------|
| 1 | GPX 複数読み込み（D&D / ファイルダイアログ）・マージ・個別削除・全クリア | `app.ts` + `gpxParser.ts` |
| 2 | **GeoShutter 自動読み込み**: `~/Dropbox/アプリ/GeoShutter/` の GPX をファイル名の日付（`GeoShutter_YYYY-MM-DD[_YYYY-MM-DD]`）と写真の撮影期間 ±2 日で突き合わせて自動ロード | `app.ts` |
| 3 | 写真フォルダ読み込み: JPEG（`.jpg`/`.jpeg`）を再帰なし列挙。起動時に前回フォルダを自動スキャン。読み込み進捗オーバーレイ | `main.ts` + `app.ts` |
| 4 | EXIF 一括読み取り: `DateTimeOriginal` / `OffsetTimeOriginal` / `OffsetTime`（フォールバック）/ GPS 有無 | exiftool `-stay_open` デーモン |
| 5 | UTC 変換: `DateTimeOriginal + OffsetTimeOriginal` → UTC。Offset 欠落時は手動オフセット（UTC-12〜+14）にフォールバック。手動モードは全ファイル一律適用 | `exifReader.ts` + `matcher.ts` |
| 6 | マッチング: UTC 昇順の GPX ポイントをバイナリサーチで最近傍検索 → `maxTimeDiff`（既定 3600 秒）以内なら採用 | `matcher.ts` |
| 7 | **静止ギャップ補完**: 時間差超過時、撮影時刻を挟む前後 2 ポイントの距離（haversine）が `stationaryGapMaxDist`（既定 50m）以内なら前ポイントを採用（記録停止中の滞在と判断） | `matcher.ts` |
| 8 | 既存 GPS の上書き制御: `hasGps && !overwriteGps` → スキップ | `matcher.ts` |
| 9 | ステータス管理: `pending / ok / done / warning / skip / error` とラベル（✓ マッチ済み / ✓ 静止補完 / ⚠ 時間差 / ⚠ GPXなし / ⚠ EXIFなし / — スキップ など） | `matcher.ts` |
| 10 | GPS 書き込み: `GPSLatitude(Ref)` / `GPSLongitude(Ref)` / `GPSAltitude(Ref)` | `main.ts` |
| 11 | **撮影日時の現地時刻書き換え**: マッチ座標からタイムゾーンを求め、`DateTimeOriginal` を現地時刻へ、`OffsetTimeOriginal` / `OffsetTime` / `OffsetTimeDigitized` をそのオフセットへ書き換え（`datetimeRaw` が空の写真は対象外） | `main.ts`（geo-tz） |
| 12 | 一括付与: ✓（ok）のみ書き込み、⚠ は自動スキップ。実行前に確認ダイアログ、進捗バー、成功/失敗集計 | `app.ts` |
| 13 | 地図表示: GPX トラック線（白縁取り＋黒線）、写真ピン（赤）、選択ピン（青）、ピン⇔テーブル行の双方向選択連動、選択時パン、標準/衛星切替 | `mapHandler.ts` |
| 14 | 写真テーブル: ファイル名 / 撮影時刻 / GPX 時刻（現地表示）/ 座標 / 時間差 / 状態 の 6 列。全列ソート可（既定: UTC 昇順） | `app.ts` |
| 15 | プレビューパネル: サムネイル＋ファイル名・撮影時刻・GPX 時刻・座標・高度・時間差・状態 | `app.ts` |
| 16 | 設定永続化: `photoFolder` / `tzMode` / `tzOffset` / `overwriteGps` / `maxTimeDiff` / `stationaryGapFill` / `stationaryGapMaxDist`、ペイン寸法 | electron-store / localStorage |

### 移植しない（Electron 固有・統合で不要）

- F12 DevTools トグル・CSP 設定・BrowserWindow 管理（ウィンドウ枠は統合アプリ側の責務）
- exiftool 存在チェックと警告バナー（ImageIO 化で依存自体が消える）
- IPC の photoFolder 配下パス検証（レンダラー分離のセキュリティ対策。ネイティブでは不要）
- サムネイルの Base64 経由読み込み（`NSImage(contentsOf:)` で直接読む）

## 3. 技術置換の方針

### 3.1 EXIF 読み書き: 読み取りは ImageIO、書き込みは exiftool（当初計画から変更）

**読み取り**: `CGImageSourceCopyPropertiesAtIndex`（`kCGImageSourceShouldCache: false`）で
Exif 辞書（`DateTimeOriginal` / `OffsetTimeOriginal` / `OffsetTime`）と GPS 辞書の有無を取得。
画像デコードは走らないため高速。`TaskGroup` で並列化し、exiftool デーモン＋200 件バッチの
仕組みは丸ごと不要になる（進捗表示は維持）。

**書き込み**: 当初は `CGImageDestinationCopyImageSource`（ImageIO、画像データを再エンコード
せずメタデータだけ差し替える API）で無劣化書き込みを狙ったが、**実写真での検証で Sony 機の
HDR 撮影による MPF 形式 Gain Map（JPEG 内の補助画像）が壊れる**（`MPImageType` が
`Undefined` 化）ことが判明し、回避策も見つからなかった（詳細は旧実装のコメントとして
`GpsWriter.swift` の git 履歴に残る）。画素本体・EXIF全体・GPS/日時は無劣化で正しく
書き込まれていたが、HDR 表示の喪失という実害があるため許容できないと判断し、
**元 GeoTagger と同じ exiftool プロセス起動方式に戻した**:

- `GpsWriter.detectExiftool()` が Homebrew の既知パス
  （`/opt/homebrew/bin/exiftool` → `/usr/local/bin/exiftool` → `/usr/bin/exiftool`）を
  順に探す（元 `main.ts` の `EXIFTOOL_PATH` 解決と同じ方式。パッケージ済みアプリは
  シェルの PATH を継承しないため）
- `Process` で 1 ファイルにつき 1 回 exiftool を起動し、`-overwrite_original` で
  無劣化上書き（バックアップファイルは作らない）
- 書き込むタグ（元実装と同一）:
  - `GPSLatitude` + `GPSLatitudeRef`(N/S)、`GPSLongitude` + `GPSLongitudeRef`(E/W)
  - 高度がある場合のみ `GPSAltitude` + `GPSAltitudeRef`(0/1)
  - `utcTime` と `datetimeRaw` が揃う場合のみ `DateTimeOriginal` / `OffsetTimeOriginal` /
    `OffsetTime` / `OffsetTimeDigitized`

**この変更により exiftool（brew インストール）が外部依存として復活した**（§8 完了条件を参照）。
検証結果は §7 に記載。

### 3.2 地図: Leaflet/OSM → MapKit

SwiftUI `Map`（macOS 14+ API、本プロジェクトは macOS 15 なので使用可）で置換する。

| 元機能 | MapKit 対応 |
|--------|-------------|
| GPX トラック線（白縁取り＋黒線 2 本描画） | `MapPolyline` を 2 本重ねる（stroke 幅 6 白 / 2 黒）。ポイント数十万件はポリライン用に間引き（Douglas-Peucker か単純間引き。マッチングは全点のまま） |
| 写真ピン（赤/青 SVG） | `Annotation` ＋ SwiftUI カスタムビュー（選択状態で色切替） |
| ピンクリック → 行選択 / 行クリック → ピン強調＋パン | 選択状態を ViewModel で共有し、`MapCameraPosition` を更新（ズーム維持でパン） |
| 標準 / 衛星切替（OSM ⇔ Esri） | `.mapStyle(.standard)` ⇔ `.mapStyle(.hybrid)` をボタンでトグル |
| トラック読み込み時の fitBounds | `MapCameraPosition.rect(...)` に境界矩形＋パディングを設定 |

### 3.3 座標→タイムゾーン: geo-tz → オフライン Swift パッケージ

第一候補は **SwiftTimeZoneLookup**（SPM、タイムゾーン境界データ同梱・オフライン動作）。

- 座標 → IANA タイムゾーン名（例 `America/Denver`）→ `Foundation.TimeZone(identifier:)` →
  `secondsFromGMT(for: utcDate)` でその**時点の**オフセットを取得（DST も Foundation が処理。
  geo-tz ＋ sv ロケール文字列操作より堅牢）
- オフセット文字列（`±HH:MM`）と現地時刻の `YYYY:MM:DD HH:MM:SS` 文字列を生成して書き込む
- geo-tz の `preCache()` 相当として、ルックアップテーブルはタブ初回表示時に一度だけ初期化
- 採用前に GT1 でライセンス・データサイズ・境界精度を確認。不適なら代替
  （tz-lookup 系の軽量実装の移植）に切り替える

### 3.4 その他の置換

| 元 | Swift 置換 |
|----|-----------|
| electron-store / localStorage | `@AppStorage`（UserDefaults）。キーは `geoTagger` プレフィックスで統合アプリ内の衝突を回避 |
| DOMParser による GPX パース | `Foundation.XMLParser`（ストリーミング型。60 万ポイント級でも全 DOM を作らない） |
| `Date` / 文字列操作の日時処理 | `DateComponents` ＋ `TimeZone` で明示的に変換（暗黙のロケール依存を排除） |
| confirm / alert | SwiftUI `.confirmationDialog` / `.alert` |
| ペインリサイザー（自作 mousedown 実装） | `HSplitView` / `VSplitView`（寸法は AppStorage に保存） |

## 4. アーキテクチャ

RAW-Trash と同じ「**Core パッケージ＋専用タブ**」パターンを採る。ジオタグ付与は
GPX・地図・マッチングを持つ独自パイプラインで、変換系の共通シェル
（`PhotoKitShared.AppViewModel<F>`：ドロップ→probe→変換）には乗らない。

```
JPPhotoTools/
├─ App/
│  ├─ project.yml               GeoTaggerCore を path 参照に追加
│  └─ Sources/
│     ├─ ContentView.swift      4 タブ目「ジオタグ」を追加
│     └─ GeoTagger/             タブ UI（App 層。新規）
│        ├─ GeoTaggerTab.swift      タブルート（HSplitView: サイドバー | 右ペイン）
│        ├─ GeoTaggerViewModel.swift 状態と操作（@MainActor / ObservableObject）
│        ├─ GeoMapView.swift        MapKit ラッパ（トラック・ピン・選択連動）
│        ├─ PhotoTableView.swift    ソート可能テーブル（SwiftUI Table）
│        ├─ PhotoPreviewPane.swift  プレビューパネル
│        └─ GpxSidebarView.swift    GPX リスト・フォルダ・TZ/しきい値設定
└─ Packages/
   └─ GeoTaggerCore/            ロジック層（新規・UI 非依存・テスト付き）
      ├─ Sources/GeoTaggerCore/
      │  ├─ GpxParser.swift         XMLParser で <trkpt> 抽出・UTC 昇順ソート・マージ
      │  ├─ ExifReader.swift        ImageIO 読み取り → PhotoItem 正規化
      │  ├─ Matcher.swift           バイナリサーチ・haversine・静止ギャップ補完
      │  ├─ GpsWriter.swift         ImageIO 無劣化メタデータ書き込み
      │  ├─ TimeZoneResolver.swift  座標→TZ 名→オフセット/現地時刻文字列
      │  ├─ GeoShutterLocator.swift ファイル名日付パースと期間フィルタ
      │  └─ Models.swift            GpxPoint / GpxData / PhotoItem / MatchResult / MatchOptions
      └─ Tests/GeoTaggerCoreTests/
```

- 名前空間衝突（GainForge/JpegResizer が App 層をパッケージ化した理由）は新規コードのため
  発生しない。タブ UI は RawTrashTab と同様に App ターゲット直下へ置き、パッケージ化の
  ボイラープレート（public 修飾・init 公開）を避ける
- 設計原則を踏襲: **ロジックは必ず Core に置き、UI からは Core の関数越しに呼ぶ**。
  マッチング・EXIF 読み書き・TZ 変換はすべて GeoTaggerCore に閉じ込め、ユニットテストを付ける

## 5. 詳細設計

### 5.1 GeoTaggerCore（ロジック層）

型は元 `types.ts` の 1:1 移植（Swift の値型・enum に写す）:

```swift
struct GpxPoint: Sendable { let lat, lon: Double; let ele: Double?; let time: Date }
struct GpxData: Sendable { let points: [GpxPoint]; let dateMin, dateMax: Date? }
struct PhotoItem: Sendable {
    let url: URL
    let datetimeRaw: String        // "2026:04:13 04:52:50"（EXIF 原文）
    let offsetStr: String?         // "-08:00"（OffsetTimeOriginal → OffsetTime の順）
    let datetime: Date?            // UTC 変換済み（offsetStr がなければ nil）
    let hasGps: Bool
}
enum MatchStatus: Sendable { case pending, ok, done, warning, skip, error }
struct MatchResult: Sendable { /* PhotoItem + utcTime / status / statusLabel / match(GpxPoint+diffSec) */ }
struct MatchOptions: Sendable {
    var maxTimeDiff: TimeInterval        // 既定 3600
    var overwriteGps: Bool               // 既定 false
    var tzMode: TzMode                   // .auto / .manual、既定 .auto
    var tzOffsetHours: Double            // 既定 -8
    var stationaryGapFill: Bool          // 既定 true
    var stationaryGapMaxDist: Double     // 既定 50 (m)
}
```

- **Matcher**: `matchAll` / `binarySearchNearest` / `findStationaryGap` / `haversineMeters` /
  `fmtDiff`（秒/分/時間の表示整形）を挙動そのまま移植。純関数なのでテストが書きやすい
- **GpxParser**: `XMLParser` デリゲートで `trkpt@lat/lon` と `<time>` `<ele>` を拾う。
  lat/lon/time が欠けた点は捨てる（元実装と同じ）。複数ファイルのマージ＋時刻ソートも Core
- **ExifReader**: ImageIO で読み、`OffsetTimeOriginal ?? OffsetTime` のフォールバック順を維持
- **GpsWriter**: §3.1 の方式。1 件 = 1 関数 `writeGps(to:lat:lon:ele:localRewrite:) throws`
- **TimeZoneResolver**: §3.3 の方式。TZ 名が引けない座標（公海など）は日時書き換えを
  スキップして GPS のみ書く（元実装の `calcOffsetStr` 失敗時と同じ挙動）

### 5.2 タブ UI（App 層）

元のレイアウトをタブ内で再現する:

```
┌──────────────┬───────────────────────────────┐
│ サイドバー    │  地図（MapKit）                │
│  GPX リスト   │   トラック線＋写真ピン          │
│  写真フォルダ  ├───────────────────────────────┤ ← VSplitView
│  TZ 設定      │  プレビュー（選択写真＋メタ情報） │
│  しきい値設定  ├───────────────────────────────┤
│  [付与]      │  写真テーブル（6 列・ソート可）    │
└──────────────┴───────────────────────────────┘
```

- **GeoTaggerViewModel**（@MainActor）が `loadedGpxFiles` / `photoItems` / `matchResults` /
  `selection` を保持。GPX 追加・フォルダ読込・設定変更のたびに `runPreview()`（= Core の
  `matchAll`）を再実行する — 元アプリの「プレビュー」ボタン相当は自動実行に寄せつつ、
  挙動（どの契機で再マッチするか）は元コードと同じ契機に揃える
- **テーブル**: SwiftUI `Table` ＋ `KeyPathComparator` でソート（既定: UTC 昇順）。
  状態列は色付き（ok=緑 / warning=橙 / error=赤 / skip=灰）
- **D&D**: `.dropDestination(for: URL.self)` で `.gpx` のみ受け付け（重複パスは無視）
- **付与**: 確認ダイアログ → ✓（ok）のみ順次書き込み → 進捗バー → `done`/`error` へ更新 →
  成功/失敗集計を表示。書き込み中は操作ボタンを無効化（`setBusy` 相当）
- **GeoShutter ボタン**: サイドバーに配置（自動読み込みの手動再実行）

### 5.3 維持すべき細かい挙動（チェックリスト）

実装・レビュー時にこのリストで突き合わせる:

- [ ] Offset 欠落ファイルがある場合の警告表示（件数付き）と手動 TZ フォールバック
- [ ] 手動モードは offsetStr の有無に関わらず**全ファイル**に手動オフセットを適用
- [ ] `datetimeRaw` すら無い写真 → `⚠ EXIF なし`（error）
- [ ] `hasGps && !overwriteGps` → `— スキップ`（マッチングすら表示しない）
- [ ] 時間差超過 → 静止ギャップ補完を先に試し、成功なら `✓ 静止補完`、失敗なら `⚠ 時間差 N`
- [ ] GPX 全削除時はマッチ結果を pending に戻す
- [ ] 写真読み込み完了時、GPX 未読込なら GeoShutter 自動読み込みを試行、読込済みなら再プレビュー
- [ ] GeoShutter ファイル名の期間判定はバッファ ±2 日（タイムゾーン差の吸収）
- [ ] 付与ボタンは ✓ 0 件・処理中は無効
- [ ] 書き込み成功 → `✓ 書込済`（done）、失敗 → `⚠ 書込失敗`（error）で個別に反映
- [ ] テーブルの GPX 時刻列は写真の offsetStr による現地表示（無ければ UTC 表記）
- [ ] GPX サマリ表示「N ポイント / 開始日 〜 終了日」

## 6. 作業ステップ（GT1〜GT3）

段階ごとにビルド＋テストを通し、一括では進めない。

- **GT1 — GeoTaggerCore の実装とテスト**
  1. パッケージ作成。`Models` / `GpxParser` / `Matcher` を移植し、ユニットテストを先に固める
     （バイナリサーチ境界・静止ギャップ・手動 TZ・スキップ判定など元ロジックの分岐を網羅）
  2. `ExifReader` / `GpsWriter` を実装。テスト用 JPEG フィクスチャ（Offset あり/なし/GPS あり）で
     読み書きの往復テスト
  3. `TimeZoneResolver`: SwiftTimeZoneLookup を導入し、既知座標（日本・米国 DST 期間中など）で
     オフセット文字列と現地時刻文字列を検証。**採用可否をここで最終判断**
  4. **exiftool 比較検証**（§7）を実施し、ImageIO 書き込みの互換性を確認

- **GT2 — タブ UI の実装**
  1. `GeoTaggerViewModel` とサイドバー・テーブル・プレビューを実装（地図なしで一巡動作）
  2. `GeoMapView`（MapKit）: トラック描画・間引き・ピン・選択連動・衛星切替
  3. D&D・設定永続化・進捗表示・確認ダイアログ

- **GT3 — 統合と検証**
  1. `project.yml` に GeoTaggerCore を追加、`ContentView` に 4 タブ目「ジオタグ」を追加
  2. 実データ（GeoShutter の GPX ＋ Lightroom 書き出し JPEG）で元 GeoTagger と結果を突き合わせ
     （マッチ件数・座標・ステータス・書き込み後 EXIF）
  3. §5.3 チェックリスト消化 → code-reviewer による独立レビュー → ドキュメント更新
     （実装計画.md の進捗表・アプリ概要.md の拡張候補欄）

## 7. リスクと検証計画

| リスク | 影響 | 検証・対策 |
|--------|------|-----------|
| **ImageIO 書き込みの互換性**（最大のリスク・**顕在化**） | Sony 機 HDR の Gain Map（MPF 補助画像）が壊れる（`MPImageType` が `Undefined` 化）。MakerNotes・画素本体・GPS/日時は無劣化だが HDR 表示が失われる実害あり | 実写真（HDR 撮影）で ImageIO 書き込み結果を検証し、Gain Map 破壊を確認。回避策なしと判断し、**書き込みは exiftool（`-overwrite_original`）に戻した**（読み取りは ImageIO のまま維持）。再検証: `A1_07217.jpg` の複製で `exiftool -j -a -G1` diff により GPS/DateTimeOriginal/Offset 系タグのみが変化し、`MPImage2: Gain Map Image` を含む他タグ・ファイルサイズが完全一致することを確認済み |
| SwiftTimeZoneLookup の精度・ライセンス・サイズ | 誤った現地時刻の書き込み | GT1 で geo-tz と同一座標の結果比較（境界付近・DST 切替日を含む）。不適なら代替実装へ |
| XMLParser の性能（60 万ポイント級 GPX） | 読み込みが遅い | ストリーミングパースで DOM を作らない。実測して遅ければ文字列スキャンに切替 |
| MapKit に数十万点のポリライン | 描画が重い | 表示用のみ間引き（マッチングは全点）。写真ピンは高々数百件で問題なし |
| 日時文字列処理のロケール依存 | 12 時間表記などの混入 | `DateFormatter` は `en_US_POSIX` 固定＋明示 TimeZone。テストで固定 |

## 8. 完了条件

- 4 タブ目「ジオタグ」がビルド・起動し、GPX 読み込み → マッチング → 地図/テーブル確認 →
  一括付与の一連が実データで動作する
- 書き込み後の JPEG が exiftool 検証で「GPS・日時タグが正しく、他タグ（Gain Map 含む）と
  画素が無傷」（§7 で確認済み）
- GeoTaggerCore のユニットテスト（マッチング分岐・GPX パース・EXIF 往復・TZ 変換）が緑
- §5.3 チェックリストが全項目確認済み
- 外部依存はネットワーク地図タイル（MapKit）と **brew exiftool**（§3.1 参照。GPS/日時書き込みに
  必須。ImageIO 書き込みが Sony HDR の Gain Map を壊すため当初計画から変更）のみ
