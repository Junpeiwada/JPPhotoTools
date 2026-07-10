# JpegResizer

ドロップした複数の画像を、アスペクト比を維持したまま高品質にリサイズし、JPEG として書き出す macOS 専用の SwiftUI ツール。

姉妹プロジェクト **GainForge**（SDR→HDR ゲインマップ変換ツール）の UI・アーキテクチャを踏襲し、変換の主目的を「HEIC 化」から「JPEG リサイズ」に置き換えたもの。

## 特徴

- **複数ドロップ**: 画像ファイル／フォルダをまとめてドロップ（フォルダは再帰収集）。
- **縮小のみ・アスペクト比維持**: 「存在しない解像感を作らない」設計。原寸を超える指定は原寸のまま。
- **最高品質リサンプル**: Core Image の `CILanczosScaleTransform` をリニア光で適用。
- **リサイズ方式**: 元のサイズ／総画素数（Mpix）／横幅（px）／縦幅（px）。方式ごとに値を記憶。
- **JPEG 書き出し**: 品質（0.0〜1.0）をスライダー指定。出力は入力と同じフォルダに `<元の名前>-resized.jpg`。
- **プライバシー配慮**: Exif は全除去（撮影日時・GPS・機種など）。向き（Orientation）は事前にピクセルへ焼き込んで正立させる。ICC カラープロファイルは画質維持のため保持。
- **並列バッチ処理**: コア数基準のスライディングウィンドウで並列変換。進捗・合計削減率を表示。
- **上書き確認**: 出力先に既存ファイルがあれば、上書き／別名保存／キャンセルを選択。

## アーキテクチャ

Core ライブラリ + GUI アプリの 2 層構成（変換ロジックを UI から分離）。

```
JpegResizer/
├── Package.swift                 # SwiftPM: Core ライブラリ + CLI
├── Sources/
│   ├── JpegResizerCore/          # 変換ロジック（UI 非依存・テスト可能）
│   │   ├── JpegResizer.swift     # convert(input:output:quality:resize:overwrite:)
│   │   ├── ResizeMode.swift      # ResizeMode / ResizeKind / ResizePlanner
│   │   ├── OutputPlanner.swift   # 出力先計画・上書き判定・命名（-resized.jpg）
│   │   ├── ConversionResult.swift
│   │   └── JpegResizerError.swift
│   └── JpegResizerCLI/           # 動作確認用 CLI（jpegresizer）
├── Tests/JpegResizerCoreTests/   # リサイズ計画・出力計画の回帰テスト
└── App/                          # XcodeGen 生成の SwiftUI アプリ
    ├── project.yml
    ├── Sources/                  # JpegResizerApp / ContentView / *View / AppViewModel など
    └── Tests/                    # AppViewModelTests
```

## ビルド

### Core ライブラリ・CLI・テスト（SwiftPM）

```bash
swift build          # Core + CLI をビルド
swift test           # Core の回帰テスト
```

CLI の使い方:

```bash
swift run jpegresizer -w 1920 ~/Pictures        # 横幅 1920px へ縮小して JPEG 出力
swift run jpegresizer --mpix 8 -q 0.85 a.png    # 総画素数 800 万・品質 0.85
jpegresizer -h                                   # ヘルプ
```

### GUI アプリ（XcodeGen + Xcode）

```bash
cd App
xcodegen generate                                # project.yml から .xcodeproj を生成
xcodebuild -scheme JpegResizer -destination 'platform=macOS' build   # ビルド
xcodebuild -scheme JpegResizer -destination 'platform=macOS' test    # アプリのテスト
```

生成した `App/JpegResizer.xcodeproj` を Xcode で開いて実行することもできる（`.xcodeproj` は Git 管理外。`xcodegen generate` で再生成する）。

## 要件

- macOS 13 以降（Apple Silicon / Intel）
- 標準フレームワークのみ（SwiftUI / AppKit / ImageIO / CoreImage）。外部パッケージ依存なし。
- ビルドに [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

## 設計ドキュメント

- [Docs/設計-全体の構成.md](Docs/設計-全体の構成.md)
