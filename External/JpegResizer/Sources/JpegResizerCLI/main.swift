// JpegResizerCLI / main.swift
// 変換ロジックは持たず、すべて JpegResizerCore に委譲する薄いラッパ。
// Core の動作確認・バッチ処理用。GUI と同じ命名規則（<stem>-resized.jpg・入力と同じフォルダ）で書き出す。

import Foundation
import JpegResizerCore

func errPrint(_ s: String) {
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
}

func mb(_ bytes: Int) -> String { String(format: "%.1fMB", Double(bytes) / 1_048_576.0) }

// ---- 引数パース ----
var quality = 0.85
var allowOverwrite = false
var resize: ResizeMode = .original
var inputs: [String] = []

let argv = CommandLine.arguments
var argi = 1
while argi < argv.count {
    let a = argv[argi]
    switch a {
    case "-q":
        argi += 1
        if argi < argv.count, let q = Double(argv[argi]) { quality = max(0.0, min(1.0, q)) }
    case "-y", "--overwrite":
        allowOverwrite = true
    case "--mpix":
        argi += 1
        if argi < argv.count, let mp = Double(argv[argi]), mp > 0 { resize = .megapixels(mp) }
    case "-w", "--width":
        argi += 1
        if argi < argv.count, let px = Int(argv[argi]), px > 0 { resize = .fitWidth(px) }
    case "--height":
        argi += 1
        if argi < argv.count, let px = Int(argv[argi]), px > 0 { resize = .fitHeight(px) }
    case "-h", "--help":
        print("使い方: jpegresizer [-q 0.0-1.0] [-y] [--mpix N | -w px | --height px] <入力ファイル/フォルダ ...>")
        print("  -q            JPEG 品質（既定 0.85）")
        print("  -y            既存の出力ファイルを上書き（既定はスキップ）")
        print("  --mpix N      アスペクト維持で総画素数(百万画素)へ縮小（例 --mpix 8）")
        print("  -w, --width px   アスペクト維持で横幅(px)へ縮小")
        print("  --height px      アスペクト維持で縦幅(px)へ縮小")
        print("  ※ リサイズは縮小のみ（原寸超え指定は原寸のまま）。3方式は最後の指定が有効。")
        print("  ※ 出力は入力と同じフォルダに <元の名前>-resized.jpg。Exif は除去・向きは焼き込み・ICC は保持。")
        exit(0)
    default:
        inputs.append(a)
    }
    argi += 1
}

if inputs.isEmpty {
    errPrint("入力がありません。-h でヘルプ。")
    exit(1)
}

// ---- 入力を画像ファイル一覧に展開（フォルダは再帰）----
let files = inputs.flatMap { JpegResizer.collectInputImages(URL(fileURLWithPath: $0)) }
if files.isEmpty {
    errPrint("変換対象の画像が見つかりません。")
    exit(1)
}

// ---- 出力先を事前計画 ----
// GUI と同じ OutputPlanner を通し、バッチ内で出力名が衝突する行は必ず連番でずらす
// （拡張子違いの同名 photo.jpg / photo.png が同じ photo-resized.jpg に落ちて取り違え・
// 無言上書きするのを防ぐ）。allowOverwriteExisting: true でディスク既存は同名のまま計画し、
// 実際に上書きするか（-y）は convert(overwrite:) 側で判定する（既定はスキップ挙動を維持）。
let targets = files.map { (id: UUID(), input: $0) }
let plans = OutputPlanner.plan(
    targets: targets, allowOverwriteExisting: true,
    fileExists: { FileManager.default.fileExists(atPath: $0.path) })

// ---- 変換ループ ----
var ok = 0, skipped = 0, failed = 0
for plan in plans {
    let inURL = plan.input
    let outURL = plan.output
    let base = inURL.lastPathComponent

    do {
        let result = try JpegResizer.convert(
            input: inURL, output: outURL, quality: quality, resize: resize, overwrite: allowOverwrite
        )
        let ratio = result.sizeRatio.map { Int(100.0 * $0) } ?? 0
        let dim = "\(Int(result.outputPixelSize.width))×\(Int(result.outputPixelSize.height))"
        print("✓  \(base) → \(result.outputURL.lastPathComponent) [\(dim)]: \(mb(result.inputBytes)) → \(mb(result.outputBytes)) (\(ratio)%)  q=\(quality)")
        ok += 1
    } catch JpegResizerError.outputExists(let out) {
        print("⏭  \(base): 既存ファイルあり（\(out.lastPathComponent)）→ スキップ（-y で上書き）")
        skipped += 1
    } catch {
        print("✗  \(base): \(error.localizedDescription)")
        failed += 1
    }
}
print("---")
print("完了: 成功 \(ok) / スキップ \(skipped) / 失敗 \(failed)")
exit(failed > 0 ? 1 : 0)
