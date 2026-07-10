import Foundation

/// RAW/JPG ペアの仕分けロジック。UI 非依存・`FileManager` のみで完結する（外部依存なし）。
///
/// 元 Electron 実装（RAW-Trash `src/main/sorter.ts`）の `sortFiles()` を Swift へ 1:1 移植したもの。
/// 対象フォルダ**直下のみ**を走査し（再帰なし）、次の規則で3つのサブフォルダへ仕分ける:
///
///   - `Del/` … 同名 JPG を持たない孤立 RAW
///   - `RAW/` … 同名 JPG が存在する（ペアの揃った）RAW
///   - `JPG/` … すべての JPG（ペアの有無を問わず無条件）
///
/// RAW でも JPG でもないファイル（`.DS_Store` や他拡張子）は移動せずそのまま残す。
public enum RawTrash {

    /// 対応する RAW 拡張子（Sony/Olympus/Canon）。比較は小文字化して行うため大小は問わない。
    public static let rawExtensions: Set<String> = ["arw", "orf", "cr3", "cr2"]

    /// JPG とみなす拡張子。比較は小文字化して行う。
    public static let jpgExtensions: Set<String> = ["jpg", "jpeg"]

    /// 仕分け結果の件数。`total` は `deleted + raw + jpg`（その他ファイルは含めない）。
    public struct SortResult: Equatable, Sendable {
        public let total: Int
        public let deleted: Int
        public let raw: Int
        public let jpg: Int

        public init(total: Int, deleted: Int, raw: Int, jpg: Int) {
            self.total = total
            self.deleted = deleted
            self.raw = raw
            self.jpg = jpg
        }
    }

    public enum SortError: Error, LocalizedError, Equatable {
        case folderNotFound(URL)

        public var errorDescription: String? {
            switch self {
            case .folderNotFound(let url):
                return "フォルダが存在しません: \(url.path)"
            }
        }
    }

    /// 対象フォルダを仕分ける。
    ///
    /// 元実装同様に **2 パス**で処理する:
    ///   1. まず JPG の stem 集合を作り、それに含まれない孤立 RAW を `Del/` へ移動する。
    ///   2. その後フォルダを再走査し、残った RAW を `RAW/`、JPG を `JPG/` へ移動する。
    /// 1 パスにまとめると JPG が先に `JPG/` へ移動して孤立 RAW 判定が壊れるため、順序を保つ。
    @discardableResult
    public static func sort(folderPath url: URL, fileManager fm: FileManager = .default) throws -> SortResult {
        guard directoryExists(url, fm: fm) else {
            throw SortError.folderNotFound(url)
        }

        let delDir = url.appendingPathComponent("Del")
        let rawDir = url.appendingPathComponent("RAW")
        let jpgDir = url.appendingPathComponent("JPG")
        for dir in [delDir, rawDir, jpgDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // --- パス1: 孤立 RAW を Del/ へ ---
        let firstPass = try regularFiles(in: url, fm: fm)
        let jpgStems = Set(
            firstPass
                .filter { jpgExtensions.contains($0.pathExtension.lowercased()) }
                .map { stem(of: $0) }
        )

        var deleted = 0
        for file in firstPass where rawExtensions.contains(file.pathExtension.lowercased()) {
            if !jpgStems.contains(stem(of: file)) {
                try move(file, into: delDir, fm: fm)
                deleted += 1
            }
        }

        // --- パス2: 残りを RAW/ JPG/ へ（フォルダを再走査） ---
        let secondPass = try regularFiles(in: url, fm: fm)
        var raw = 0
        var jpg = 0
        for file in secondPass {
            let ext = file.pathExtension.lowercased()
            if rawExtensions.contains(ext) {
                try move(file, into: rawDir, fm: fm)
                raw += 1
            } else if jpgExtensions.contains(ext) {
                try move(file, into: jpgDir, fm: fm)
                jpg += 1
            }
            // それ以外（.DS_Store・他拡張子）は移動しない。
        }

        return SortResult(total: deleted + raw + jpg, deleted: deleted, raw: raw, jpg: jpg)
    }

    // MARK: - 内部ヘルパ

    /// 拡張子を除いたファイル名（stem）。ペア判定用に小文字化して返す。
    private static func stem(of url: URL) -> String {
        url.deletingPathExtension().lastPathComponent.lowercased()
    }

    /// 対象フォルダ直下の通常ファイルのみ（ディレクトリを除外、再帰なし）。
    private static func regularFiles(in url: URL, fm: FileManager) throws -> [URL] {
        let entries = try fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        )
        return try entries.filter { entry in
            let values = try entry.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true
        }
    }

    /// `src` を `destDir` 直下へ移動する。宛先に同名があれば連番（`name_1.ext`）で退避し、
    /// 写真の上書き消失を防ぐ（元 Electron 実装は上書きだが、安全側へ倒した）。
    /// まず `moveItem`、失敗時はクロスボリューム対策で copy + remove にフォールバックする。
    private static func move(_ src: URL, into destDir: URL, fm: FileManager) throws {
        let dest = uniqueDestination(for: src.lastPathComponent, in: destDir, fm: fm)
        do {
            try fm.moveItem(at: src, to: dest)
        } catch let moveError {
            // クロスボリューム等で rename できないときの copy + remove。ただし copy 成功後に
            // remove が失敗すると同一写真が 2 箇所に残る（複製）ため、その場合はコピー先を
            // 掃除して元 moveItem のエラーを投げ直す。「移動」の不変条件（元が消える）を守り、
            // 失敗を握りつぶさず呼び出し元へ伝える。
            do {
                try fm.copyItem(at: src, to: dest)
                try fm.removeItem(at: src)
            } catch {
                try? fm.removeItem(at: dest)
                throw moveError
            }
        }
    }

    /// `destDir` 内で衝突しないファイル URL を返す。`name.ext` が既にあれば
    /// `name_1.ext`, `name_2.ext`, … と番号を上げていく。
    private static func uniqueDestination(for fileName: String, in destDir: URL, fm: FileManager) -> URL {
        let candidate = destDir.appendingPathComponent(fileName)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }

        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var n = 1
        while true {
            let numbered = ext.isEmpty ? "\(base)_\(n)" : "\(base)_\(n).\(ext)"
            let url = destDir.appendingPathComponent(numbered)
            if !fm.fileExists(atPath: url.path) { return url }
            n += 1
        }
    }

    private static func directoryExists(_ url: URL, fm: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
