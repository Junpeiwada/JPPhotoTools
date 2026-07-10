import Foundation
import AppKit

/// ファイル行の処理状態（画面仕様の状態遷移に対応）。変換系タブ共通。
///
/// `.existing`（変換前から対応出力が在り、変換せずプレビュー可能）は GainForge 固有の概念だが、
/// enum を機能ごとに分岐させると共通シェルがジェネリックにならないため、共通の状態集合として
/// 持たせる。JpegResizer は `.existing` へ遷移させない（生成しないだけ）。遷移させるかどうかは
/// 各機能の probe（`FeatureShell.probe` が返す `ProbeResult.existingOutput`）が決める。
public enum RowStatus: Equatable, Sendable {
    case waiting      // 待機
    case converting   // 変換中
    case done         // 完了
    case existing     // 既存（変換前から対応出力があり、変換せずプレビュー可能）— GainForge のみ使用
    case error        // エラー
    case skipped      // スキップ
}

/// 画面全体の状態。
public enum AppPhase: Equatable, Sendable {
    case empty        // 一覧なし
    case ready        // 待機行あり
    case converting   // バッチ実行中
    case finished     // 全行が完了/エラー/スキップ
}

/// 既存ファイルの上書き確認ダイアログでの選択。
public enum OverwriteResolution: Sendable {
    case overwrite   // 既存を上書きして続行
    case rename      // 既存を残し、別名（連番）で保存
    case cancel      // 変換しない
}

/// 一覧の 1 行 = 1 入力ファイル。変換キュー兼結果一覧。
///
/// 共通コア（id/inputURL/thumbnail/status/bytes/outputURL/errorMessage）に加え、機能固有の
/// 付加情報を型パラメータ `Extra` で持たせる（GainForge: ゲインマップ状態 / JpegResizer: 寸法）。
/// `Extra` は Task 境界を越えて probe 結果を差し込むため `Sendable`、Table の再描画判定のため
/// `Equatable` を要求する。
public struct FileItem<Extra: Equatable & Sendable>: Identifiable, Equatable {
    public let id = UUID()
    public let inputURL: URL

    public var thumbnail: NSImage?
    public var status: RowStatus = .waiting

    public var inputBytes: Int?
    public var outputBytes: Int?
    public var outputURL: URL?
    public var errorMessage: String?

    /// 機能固有の付加情報。初期値は各機能が用意する（`Extra` の初期状態）。
    public var extra: Extra

    public init(inputURL: URL, extra: Extra) {
        self.inputURL = inputURL
        self.extra = extra
    }

    public var displayName: String { inputURL.lastPathComponent }

    // 表示に関わる全フィールドを比較する。`id` だけで比較すると SwiftUI の Table が
    // 「中身が変わっていない」と誤判定してセルを再描画しない。thumbnail は NSImage（クラス）
    // なので参照同一性（===）で比較する。Extra は機能固有の Equatable に委ねる。
    public static func == (lhs: FileItem<Extra>, rhs: FileItem<Extra>) -> Bool {
        lhs.id == rhs.id &&
        lhs.status == rhs.status &&
        lhs.inputBytes == rhs.inputBytes &&
        lhs.outputBytes == rhs.outputBytes &&
        lhs.outputURL == rhs.outputURL &&
        lhs.errorMessage == rhs.errorMessage &&
        lhs.extra == rhs.extra &&
        lhs.thumbnail === rhs.thumbnail
    }
}
