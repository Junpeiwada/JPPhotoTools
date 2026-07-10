import Foundation

/// probe 1 件の結果（Task 境界を越えるため Sendable）。サムネ PNG・入力サイズは共通、
/// `extra` は機能固有、`existingOutput` は既存出力（あれば `.existing` へ遷移）。
/// プロトコル内にはネストできないため、トップレベルのジェネリック型として定義する。
public struct ProbeResult<Extra: Equatable & Sendable>: Sendable {
    public var inputBytes: Int
    public var thumbnailPNG: Data?
    public var extra: Extra
    /// 変換前から在る対応出力（GainForge のみ非 nil を返し得る）。
    public var existingOutput: (url: URL, bytes: Int)?
    public init(inputBytes: Int, thumbnailPNG: Data?, extra: Extra,
                existingOutput: (url: URL, bytes: Int)? = nil) {
        self.inputBytes = inputBytes
        self.thumbnailPNG = thumbnailPNG
        self.extra = extra
        self.existingOutput = existingOutput
    }
}

/// 変換 1 件の成功結果（Task 境界を越えるため Sendable）。共通の出力メタに加え、`resultExtra` で
/// 機能固有の付加情報（JpegResizer: 出力寸法など）を変換完了時に行へ反映できる。nil なら probe 済みの
/// extra を維持する。
public struct ConversionSuccess<Extra: Equatable & Sendable>: Sendable {
    public var outputURL: URL
    public var outputBytes: Int
    public var inputBytes: Int
    /// 変換完了時に上書き反映する機能固有の付加情報（省略可）。
    public var resultExtra: Extra?
    public init(outputURL: URL, outputBytes: Int, inputBytes: Int, resultExtra: Extra? = nil) {
        self.outputURL = outputURL
        self.outputBytes = outputBytes
        self.inputBytes = inputBytes
        self.resultExtra = resultExtra
    }
}

/// 変換系タブ（GainForge / JpegResizer）が共通シェル `AppViewModel` に差し込む「機能の定義」。
///
/// 共通シェルはドロップ受け入れ・probe スロットル・スライディングウィンドウ並列変換・上書き確認
/// という骨格だけを持ち、機能ごとに変わる部分をこのプロトコル経由で注入する。差し替えるのは
/// 実質「①入力収集 ②probe 内容 ③変換 ④出力計画」だけで、GainForge 固有の枝（既存出力検出→
/// `.existing`、ML 降格通知）は**任意フック**（デフォルト実装あり）として持たせ、JpegResizer は
/// 実装しないことで基盤をクリーンに保つ。
///
/// すべてのメソッドは `Sendable` な値だけをやり取りし、重い処理はバックグラウンドで実行できる。
public protocol FeatureShell: Sendable {
    /// 行の機能固有付加情報（GainForge: ゲインマップ状態 / JpegResizer: 寸法）。
    associatedtype Extra: Equatable & Sendable
    /// probe 前の `Extra` 初期値。
    var initialExtra: Extra { get }

    /// 変換設定のスナップショット（バッチ開始時に確定し、Task 境界を越える）。
    associatedtype Settings: Sendable

    /// ドロップされた URL 群から入力画像を収集する（フォルダは再帰）。バックグラウンド実行。
    func collectInputs(_ urls: [URL]) -> [URL]

    /// 1 入力を probe する（サイズ・サムネ・機能固有メタ・既存出力）。バックグラウンド実行。
    /// `settings` は既存出力検出が出力先設定に依存する機能（GainForge）のために渡す。
    func probe(_ url: URL, settings: Settings) -> ProbeResult<Extra>

    /// 1 入力を変換する。出力先・上書き可否は共通シェルが計画済みの値を渡す。バックグラウンド実行。
    /// 成功なら `ConversionSuccess`、失敗なら Error を throw。
    /// 「計画外の既存ファイルへの衝突」は `FeatureConversionError.blocked` を throw するとバッチを止める。
    func convert(input: URL, output: URL, overwrite: Bool, settings: Settings) throws
        -> ConversionSuccess<Extra>

    /// 出力計画に使う「入力 → 出力先ディレクトリ」。既定は入力と同じフォルダ。
    func outputDirectory(for input: URL, settings: Settings) -> URL
    /// 出力計画に使う「(stem, index) → 出力ファイル名」（拡張子込み）。
    func outputFileName(stem: String, index: Int, settings: Settings) -> String

    /// バッチ内の出力先衝突判定を大小無視で行うか。APFS（case-insensitive）で `Photo.jpg` と
    /// `photo.jpg` を同一出力先とみなして連番回避したい機能は true（既定 false）。
    var outputIsCaseInsensitive: Bool { get }
}

/// 変換の失敗種別（共通シェルが解釈する）。機能側は `convert` からこれを throw する。
public enum FeatureConversionError: Error {
    /// 計画外の既存ファイルへ衝突。以後の予期せぬ上書きを避けるためバッチを止める。
    case blocked(String)
    /// 通常の失敗。メッセージを行に表示する。
    case failed(String)
}

public extension FeatureShell {
    /// 既定の出力先は入力と同じフォルダ（JpegResizer 相当）。
    func outputDirectory(for input: URL, settings: Settings) -> URL {
        input.deletingLastPathComponent()
    }
    /// 既定は大小区別（GainForge の従来挙動）。
    var outputIsCaseInsensitive: Bool { false }
}
