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
/// 出力先は常に **入力と同じフォルダ**、ファイル名は `<元の名前>-resized.jpg`。
///
/// - バッチ内で出力先が衝突する行は必ず連番でずらし、片方が他方を消さないようにする
///   （並列変換時の取り違え・上書き事故を設計段階で排除する）。
/// - ディスク上の既存ファイルは `allowOverwriteExisting` に従う:
///   true ならそのまま使い `willOverwrite = true`（上書き予定）、
///   false なら連番でずらして既存を温存する。
public enum OutputPlanner {

    /// 出力 JPEG の拡張子（入力形式によらず常に `.jpg`）。
    public static let outputExtension = "jpg"
    /// 出力ファイル名に付与する接尾辞（`<stem>-resized.jpg`）。
    public static let suffix = "-resized"

    /// 出力先を計画する。`fileExists` は既存判定の注入点（テストでは仮想ファイル系を渡す）。
    public static func plan(
        targets: [(id: UUID, input: URL)],
        allowOverwriteExisting: Bool,
        fileExists: (URL) -> Bool
    ) -> [OutputPlan] {
        // このバッチで確保済みの出力パス。macOS 既定の APFS は case-insensitive のため、
        // キーは小文字化して照合する（`Photo-resized.jpg` と `photo-resized.jpg` を同一とみなす）。
        var reserved = Set<String>()
        var plans: [OutputPlan] = []
        for t in targets {
            let dir = t.input.deletingLastPathComponent()   // 出力先は常に入力と同じフォルダ
            let stem = t.input.deletingPathExtension().lastPathComponent

            var index = 0
            var url = candidate(dir: dir, stem: stem, index: index)
            var willOverwrite = false
            while true {
                let key = url.standardizedFileURL.path.lowercased()
                if reserved.contains(key) {                  // バッチ内衝突 → 必ずずらす
                    index += 1; url = candidate(dir: dir, stem: stem, index: index); continue
                }
                let exists = fileExists(url)
                if exists && !allowOverwriteExisting {        // 既存温存 → ずらす
                    index += 1; url = candidate(dir: dir, stem: stem, index: index); continue
                }
                willOverwrite = exists                        // 既存をそのまま使うなら上書き
                break
            }
            reserved.insert(url.standardizedFileURL.path.lowercased())
            plans.append(OutputPlan(id: t.id, input: t.input, output: url, willOverwrite: willOverwrite))
        }
        return plans
    }

    /// `<stem>-resized.jpg` / `<stem>-resized_N.jpg` の候補 URL を作る。
    public static func candidate(dir: URL, stem: String, index: Int) -> URL {
        let base = stem + suffix
        let name = index <= 0 ? "\(base).\(outputExtension)" : "\(base)_\(index).\(outputExtension)"
        return dir.appendingPathComponent(name)
    }
}
