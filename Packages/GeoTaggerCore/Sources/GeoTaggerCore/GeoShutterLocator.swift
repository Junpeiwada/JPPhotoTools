import Foundation

/// GeoShutter（iPhone アプリ）が Dropbox へ書き出す GPX の自動検出。
public enum GeoShutterLocator {
    /// ~/Dropbox/アプリ/GeoShutter
    public static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Dropbox/アプリ/GeoShutter")
    }

    private static let filenameRegex: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(pattern: "GeoShutter_(\\d{4}-\\d{2}-\\d{2})(?:_(\\d{4}-\\d{2}-\\d{2}))?") else {
            fatalError("GeoShutterLocator: 正規表現パターンが不正")
        }
        return regex
    }()

    /// "GeoShutter_YYYY-MM-DD[_YYYY-MM-DD]" を含むファイル名から期間（UTC 日の 00:00:00〜23:59:59）を得る
    public static func parseFilenameDates(_ name: String) -> (start: Date, end: Date)? {
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        guard let match = filenameRegex.firstMatch(in: name, range: range) else { return nil }

        guard let startRange = Range(match.range(at: 1), in: name) else { return nil }
        let startDateString = String(name[startRange])

        let endDateString: String
        if match.range(at: 2).location != NSNotFound, let endRange = Range(match.range(at: 2), in: name) {
            endDateString = String(name[endRange])
        } else {
            endDateString = startDateString
        }

        guard
            let start = DateFormatter.geoShutterDayStart.date(from: "\(startDateString) 00:00:00"),
            let end = DateFormatter.geoShutterDayStart.date(from: "\(endDateString) 23:59:59")
        else {
            return nil
        }

        return (start, end)
    }

    /// folder 内の .gpx のうち、写真の撮影期間（UTC）と ±2 日バッファで重なるものを返す
    public static func candidates(photoMinUTC: Date, photoMaxUTC: Date, in folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants]
        ) else {
            return []
        }

        let bufferSeconds: TimeInterval = 2 * 24 * 60 * 60

        return entries.filter { url in
            guard url.pathExtension.lowercased() == "gpx" else { return false }
            guard let (start, end) = parseFilenameDates(url.lastPathComponent) else { return false }
            return end.addingTimeInterval(bufferSeconds) >= photoMinUTC
                && start.addingTimeInterval(-bufferSeconds) <= photoMaxUTC
        }
    }
}

extension DateFormatter {
    fileprivate static let geoShutterDayStart: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
}
