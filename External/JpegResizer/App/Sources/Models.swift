import Foundation
import AppKit
import CoreGraphics

/// ファイル行の処理状態（画面仕様の状態遷移に対応）。
enum RowStatus: Equatable {
    case waiting      // 待機
    case converting   // 変換中
    case done         // 完了
    case error        // エラー
    case skipped      // スキップ
}

/// 一覧の 1 行 = 1 入力ファイル。変換キュー兼結果一覧。
struct FileItem: Identifiable, Equatable {
    let id = UUID()
    let inputURL: URL

    var thumbnail: NSImage?
    var status: RowStatus = .waiting

    /// 元寸法（Orientation 適用後の正立寸法）。probe で取得する。
    var pixelSize: CGSize?
    /// 出力寸法（変換完了後に確定）。
    var outputPixelSize: CGSize?

    var inputBytes: Int?
    var outputBytes: Int?
    var outputURL: URL?
    var errorMessage: String?

    var displayName: String { inputURL.lastPathComponent }

    // 表示に関わる全フィールドを比較する。`id` だけで比較すると SwiftUI の Table が
    // 「中身が変わっていない」と誤判定して、変換結果のセルを再描画しない。
    // thumbnail は NSImage（クラス）なので参照同一性（===）で比較する。
    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.status == rhs.status &&
        lhs.pixelSize == rhs.pixelSize &&
        lhs.outputPixelSize == rhs.outputPixelSize &&
        lhs.inputBytes == rhs.inputBytes &&
        lhs.outputBytes == rhs.outputBytes &&
        lhs.outputURL == rhs.outputURL &&
        lhs.errorMessage == rhs.errorMessage &&
        lhs.thumbnail === rhs.thumbnail
    }
}

/// 画面全体の状態。
enum AppPhase: Equatable {
    case empty        // 一覧なし
    case ready        // 待機行あり
    case converting   // バッチ実行中
    case finished     // 全行が完了/エラー/スキップ
}

/// 既存ファイルの上書き確認ダイアログでの選択。
enum OverwriteResolution {
    case overwrite   // 既存を上書きして続行
    case rename      // 既存を残し、別名（連番）で保存
    case cancel      // 変換しない
}
