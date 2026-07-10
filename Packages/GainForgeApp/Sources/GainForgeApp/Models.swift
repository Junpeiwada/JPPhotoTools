import Foundation
import PhotoKitShared

/// ゲインマップ有無の判定状態。
enum GainMapState: Equatable, Sendable {
    case checking   // 判定中
    case present    // あり
    case absent     // なし
}

/// 出力先モード。
enum OutputMode: Equatable, Sendable {
    case sameFolder         // 入力と同じフォルダ
    case customFolder       // 指定フォルダ
}

/// GainForge 固有の行付加情報（ゲインマップ有無）。
/// 共通コア（PhotoKitShared.FileItem）に組み合わせる。
struct GainForgeExtra: Equatable, Sendable {
    var gainMap: GainMapState
}

/// 一覧の 1 行 = 1 入力ファイル。共通コア（PhotoKitShared.FileItem）に
/// GainForge 固有の付加情報（`GainForgeExtra`: ゲインマップ状態）を組み合わせたもの。
/// View 側の `FileItem` 参照をなるべく変えずに済ませるための typealias。
typealias FileItem = PhotoKitShared.FileItem<GainForgeExtra>

/// 出力 HEIC を保持し、比較ビューワを開ける行か（変換完了 or 既存検出）。
/// 共通 `FileItem<Extra>` には生やせないため、GainForge 側の自由関数として用意する。
func hasComparableOutput(_ item: FileItem) -> Bool {
    item.outputURL != nil && (item.status == .done || item.status == .existing)
}

// MARK: - 既存出力（変換前から存在する HEIC）の検出

/// 入力 JPEG に対応する既存 HEIC を探す純粋ロジック（UI 非依存・テスト可能）。
///
/// 「変換しなくても変換済み（既存）として扱い、プレビューできる」ようにするための検出。
/// 入力と同じフォルダと、指定フォルダ出力時はその出力先フォルダの双方で `stem.heic` を確認する。
/// 連番（`stem_N.heic`）は対象にしない（「この入力の変換結果」と明確に言えるのは同名のみ）。
enum ExistingOutputFinder {

    /// 既存 HEIC があればその URL を、無ければ nil を返す。`fileExists` は既存判定の注入点。
    static func find(
        input: URL,
        outputMode: OutputMode,
        customFolder: URL?,
        fileExists: (URL) -> Bool
    ) -> URL? {
        let stem = input.deletingPathExtension().lastPathComponent
        var dirs: [URL] = [input.deletingLastPathComponent()]
        if outputMode == .customFolder, let customFolder { dirs.append(customFolder) }
        for dir in dirs {
            let url = dir.appendingPathComponent(stem + ".heic")
            if fileExists(url) { return url }
        }
        return nil
    }
}
