import Foundation

/// 写真と GPX ポイントの時刻マッチング（元 GeoTagger matcher.ts の 1:1 移植）。
public enum Matcher {
    /// 全写真をマッチングして MatchResult を返す。分岐は元実装と同一:
    /// 1. 手動 TZ モード or offsetStr なし → datetimeRaw + 手動オフセットで UTC 変換
    ///    （datetimeRaw もなければ `⚠ EXIF なし` error）
    /// 2. UTC 不明 → `⚠ 時刻不明` error
    /// 3. hasGps && !overwriteGps → `— スキップ` skip
    /// 4. バイナリサーチ最近傍。GPX なし → `⚠ GPXなし` warning
    /// 5. 時間差 > maxTimeDiff → 静止ギャップ補完を試行（成功 `✓ 静止補完` ok /
    ///    失敗 `⚠ 時間差 N` warning）
    /// 6. しきい値内 → `✓ マッチ済み` ok
    public static func matchAll(gpxPoints: [GpxPoint], photos: [PhotoItem], options: MatchOptions) -> [MatchResult] {
        photos.map { photo in
            var utcTime = photo.datetime

            if options.tzMode == .manual || photo.offsetStr == nil {
                guard !photo.datetimeRaw.isEmpty else {
                    return MatchResult(photo: photo, utcTime: nil, status: .error, statusLabel: "⚠ EXIF なし", match: nil)
                }
                utcTime = manualUtcTime(datetimeRaw: photo.datetimeRaw, tzOffsetHours: options.tzOffsetHours)
            }

            guard let resolvedUtcTime = utcTime else {
                return MatchResult(photo: photo, utcTime: nil, status: .error, statusLabel: "⚠ 時刻不明", match: nil)
            }

            if photo.hasGps && !options.overwriteGps {
                return MatchResult(photo: photo, utcTime: resolvedUtcTime, status: .skip, statusLabel: "— スキップ", match: nil)
            }

            guard let nearest = binarySearchNearest(gpxPoints, target: resolvedUtcTime) else {
                return MatchResult(photo: photo, utcTime: resolvedUtcTime, status: .warning, statusLabel: "⚠ GPXなし", match: nil)
            }

            let diffSec = abs(resolvedUtcTime.timeIntervalSince(nearest.time))
            let matchPt = MatchedPoint(point: nearest, diffSec: diffSec)

            if diffSec > options.maxTimeDiff {
                if options.stationaryGapFill,
                   let gapPt = findStationaryGap(gpxPoints, target: resolvedUtcTime, maxDistMeters: options.stationaryGapMaxDist) {
                    let gapDiffSec = abs(resolvedUtcTime.timeIntervalSince(gapPt.time))
                    return MatchResult(
                        photo: photo, utcTime: resolvedUtcTime, status: .ok, statusLabel: "✓ 静止補完",
                        match: MatchedPoint(point: gapPt, diffSec: gapDiffSec)
                    )
                }
                return MatchResult(
                    photo: photo, utcTime: resolvedUtcTime, status: .warning,
                    statusLabel: "⚠ 時間差 \(fmtDiff(diffSec))", match: matchPt
                )
            }

            return MatchResult(photo: photo, utcTime: resolvedUtcTime, status: .ok, statusLabel: "✓ マッチ済み", match: matchPt)
        }
    }

    /// 秒数の表示整形: 60 秒未満 "N秒" / 60 分未満 "N分" / それ以上 "N.N時間"
    public static func fmtDiff(_ sec: TimeInterval) -> String {
        if sec < 60 {
            return "\(Int(sec.rounded()))秒"
        }
        if sec < 3600 {
            return "\(Int((sec / 60).rounded()))分"
        }
        return String(format: "%.1f時間", sec / 3600)
    }

    // MARK: - 内部ロジック

    /// "2026:04:13 04:52:50" + 手動オフセット時間（例 -8.0 → "-08:00"）から UTC Date を組み立てる。
    /// 元実装 `new Date(iso + sign + hh:mm)` の 1:1 移植。パース不能なら nil
    static func manualUtcTime(datetimeRaw: String, tzOffsetHours: Double) -> Date? {
        // "yyyy:MM:dd HH:mm:ss" → "yyyy-MM-dd HH:mm:ss"
        guard let localDate = DateFormatter.exifLocal.date(from: datetimeRaw) else { return nil }

        let sign = tzOffsetHours >= 0 ? "+" : "-"
        let absHours = abs(tzOffsetHours)
        let hh = Int(absHours.rounded(.down))
        let mm = Int((absHours.truncatingRemainder(dividingBy: 1) * 60).rounded())
        let offsetSeconds = (hh * 3600 + mm * 60) * (sign == "+" ? 1 : -1)

        // localDate は「オフセットなしの壁時計値」として UTC 扱いでパースされているため、
        // 実際の UTC はそこからオフセット分を引く
        return localDate.addingTimeInterval(-TimeInterval(offsetSeconds))
    }

    static func binarySearchNearest(_ points: [GpxPoint], target: Date) -> GpxPoint? {
        guard !points.isEmpty else { return nil }
        let t = target
        var lo = 0
        var hi = points.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if points[mid].time < t {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        if lo > 0 {
            let dLo = abs(points[lo].time.timeIntervalSince(t))
            let dPrev = abs(points[lo - 1].time.timeIntervalSince(t))
            if dPrev < dLo {
                return points[lo - 1]
            }
        }
        return points[lo]
    }

    static func findStationaryGap(_ points: [GpxPoint], target: Date, maxDistMeters: Double) -> GpxPoint? {
        guard points.count >= 2 else { return nil }
        let t = target
        var lo = 0
        var hi = points.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if points[mid].time < t {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        // lo = target 以上の最初のインデックス
        guard lo > 0, lo < points.count else { return nil }
        let before = points[lo - 1]
        let after = points[lo]
        let dist = haversineMeters(lat1: before.lat, lon1: before.lon, lat2: after.lat, lon2: after.lon)
        return dist <= maxDistMeters ? before : nil
    }

    static func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6_371_000.0
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let deltaPhi = (lat2 - lat1) * .pi / 180
        let deltaLambda = (lon2 - lon1) * .pi / 180
        let a = sin(deltaPhi / 2) * sin(deltaPhi / 2)
            + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        return R * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

extension DateFormatter {
    /// EXIF 原文 "yyyy:MM:dd HH:mm:ss" をタイムゾーンなし（UTC 扱い）でパースする内部フォーマッタ。
    /// manualUtcTime はここで得た「壁時計としての UTC」からオフセット分を引いて真の UTC を得る。
    fileprivate static let exifLocal: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f
    }()
}
