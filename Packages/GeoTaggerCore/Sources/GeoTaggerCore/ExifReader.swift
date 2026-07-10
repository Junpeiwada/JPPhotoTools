import Foundation
import ImageIO
import UniformTypeIdentifiers

/// ImageIO による EXIF 読み取り（画像デコードなし）。
public enum ExifReader {
    /// フォルダ直下（再帰なし）の .jpg / .jpeg を大小無視で列挙（ファイル名昇順）
    public static func listJpegs(in folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsSubdirectoryDescendants]
        ) else {
            return []
        }

        return entries
            .filter { url in
                let ext = url.pathExtension.lowercased()
                guard ext == "jpg" || ext == "jpeg" else { return false }
                let isRegular = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
                return isRegular
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// 1 枚読み取り。DateTimeOriginal / OffsetTimeOriginal（→ OffsetTime フォールバック）/
    /// GPS 有無を取得して PhotoItem に正規化。読めないファイルは datetimeRaw 空で返す
    public static func readPhoto(at url: URL) -> PhotoItem {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options as CFDictionary) as? [CFString: Any]
        else {
            return PhotoItem(url: url, datetimeRaw: "", offsetStr: nil, datetime: nil, hasGps: false)
        }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]

        let datetimeRaw = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String) ?? ""
        // OffsetTimeOriginal がない場合（Lightroom書き出しJPGなど）は OffsetTime にフォールバック
        let offsetStr = (exif?[kCGImagePropertyExifOffsetTimeOriginal] as? String)
            ?? (exif?[kCGImagePropertyExifOffsetTime] as? String)

        let datetime = parseExifDate(datetimeRaw, offsetStr: offsetStr)

        let hasGps = (gps?[kCGImagePropertyGPSLatitude] != nil) && (gps?[kCGImagePropertyGPSLongitude] != nil)

        return PhotoItem(url: url, datetimeRaw: datetimeRaw, offsetStr: offsetStr, datetime: datetime, hasGps: hasGps)
    }

    /// 並列一括読み取り。progress は (完了数, 総数) をメインスレッド以外から呼びうる。
    /// 戻り順は urls の順序を保つ
    public static func readPhotos(at urls: [URL], progress: @escaping @Sendable (Int, Int) -> Void) async -> [PhotoItem] {
        guard !urls.isEmpty else { return [] }
        let total = urls.count

        let counter = ProgressCounter()

        let results = await withTaskGroup(of: (Int, PhotoItem).self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    let item = readPhoto(at: url)
                    let done = await counter.increment()
                    progress(done, total)
                    return (index, item)
                }
            }

            var ordered = [PhotoItem?](repeating: nil, count: total)
            for await (index, item) in group {
                ordered[index] = item
            }
            return ordered
        }

        return results.compactMap { $0 }
    }

    /// "2026:04:13 04:52:50" + "-08:00" → UTC Date（変換不能なら nil）
    public static func parseExifDate(_ datetimeRaw: String, offsetStr: String?) -> Date? {
        guard !datetimeRaw.isEmpty, let offsetStr else { return nil }
        let combined = "\(datetimeRaw) \(offsetStr)"
        return DateFormatter.exifWithOffset.date(from: combined)
    }
}

/// TaskGroup 内の完了数カウンタ（アクターで排他制御）
private actor ProgressCounter {
    private var count = 0
    func increment() -> Int {
        count += 1
        return count
    }
}

extension DateFormatter {
    /// "yyyy:MM:dd HH:mm:ss ±HH:MM" を厳密にパースする（en_US_POSIX 固定）。
    fileprivate static let exifWithOffset: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss xxx"
        return f
    }()
}
