import Foundation

/// 1 入力に対する出力先の計画。
public struct OutputPlan: Equatable, Sendable {
    public let id: UUID
    public let input: URL
    public let output: URL
    /// 出力先に既存ファイルがあり、上書きになるか。
    public let willOverwrite: Bool

    public init(id: UUID, input: URL, output: URL, willOverwrite: Bool) {
        self.id = id
        self.input = input
        self.output = output
        self.willOverwrite = willOverwrite
    }
}

/// 出力先を事前に決める純粋ロジック（UI 非依存・テスト可能）。
///
/// GainForge（出力先モード same/custom・拡張子 .heic）と JpegResizer（常に same・拡張子 .jpg）で
/// 相違があった出力計画を共通化。相違点である「入力 → 出力先ディレクトリ」と「stem+連番 →
/// 出力ファイル名」を **クロージャで注入**し、バッチ内衝突を連番で必ず回避するコアロジックを共有する。
///
/// - バッチ内で出力先が衝突する行は必ず連番でずらし、片方が他方を消さないようにする。
/// - ディスク上の既存ファイルは `allowOverwriteExisting` に従う: true ならそのまま使い
///   `willOverwrite = true`、false なら連番でずらして既存を温存する。
public enum OutputPlanner {

    /// 出力先を計画する。
    /// - Parameters:
    ///   - targets: 対象の (id, 入力 URL)。
    ///   - directoryFor: 入力 URL → 出力先ディレクトリ（機能ごとの出力先モードを吸収）。
    ///   - fileName: (stem, index) → ファイル名。index<=0 は無印、>0 は連番（拡張子も含めて機能が決める）。
    ///   - allowOverwriteExisting: 既存ファイルを上書き予定にするか。
    ///   - caseInsensitive: バッチ内衝突の照合を大小無視にするか。macOS 既定の APFS は
    ///     case-insensitive なので、`Photo.jpg` と `photo.jpg` を同一出力先とみなして連番回避
    ///     したい機能（JpegResizer）では true にする。false（GainForge の従来挙動）は大小区別。
    ///   - fileExists: 既存判定の注入点（テストでは仮想ファイル系を渡す）。
    public static func plan(
        targets: [(id: UUID, input: URL)],
        directoryFor: (URL) -> URL,
        fileName: (_ stem: String, _ index: Int) -> String,
        allowOverwriteExisting: Bool,
        caseInsensitive: Bool = false,
        fileExists: (URL) -> Bool
    ) -> [OutputPlan] {
        var reserved = Set<String>()   // このバッチで確保済みの出力パス
        var plans: [OutputPlan] = []
        func reservedKey(_ url: URL) -> String {
            let path = url.standardizedFileURL.path
            return caseInsensitive ? path.lowercased() : path
        }
        for t in targets {
            let dir = directoryFor(t.input)
            let stem = t.input.deletingPathExtension().lastPathComponent

            var index = 0
            var url = dir.appendingPathComponent(fileName(stem, index))
            var willOverwrite = false
            while true {
                let key = reservedKey(url)
                if reserved.contains(key) {                 // バッチ内衝突 → 必ずずらす
                    index += 1; url = dir.appendingPathComponent(fileName(stem, index)); continue
                }
                let exists = fileExists(url)
                if exists && !allowOverwriteExisting {       // 既存温存 → ずらす
                    index += 1; url = dir.appendingPathComponent(fileName(stem, index)); continue
                }
                willOverwrite = exists                       // 既存をそのまま使うなら上書き
                break
            }
            reserved.insert(reservedKey(url))
            plans.append(OutputPlan(id: t.id, input: t.input, output: url, willOverwrite: willOverwrite))
        }
        return plans
    }
}
