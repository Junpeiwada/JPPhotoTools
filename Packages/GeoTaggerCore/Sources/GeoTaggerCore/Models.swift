import Foundation

// MARK: - GPX

public struct GpxPoint: Sendable, Equatable {
    public let lat: Double
    public let lon: Double
    public let ele: Double?
    public let time: Date

    public init(lat: Double, lon: Double, ele: Double?, time: Date) {
        self.lat = lat
        self.lon = lon
        self.ele = ele
        self.time = time
    }
}

public struct GpxData: Sendable, Equatable {
    /// UTC 昇順ソート済み
    public let points: [GpxPoint]
    public let dateMin: Date?
    public let dateMax: Date?

    public init(points: [GpxPoint], dateMin: Date?, dateMax: Date?) {
        self.points = points
        self.dateMin = dateMin
        self.dateMax = dateMax
    }
}

// MARK: - 写真

public struct PhotoItem: Sendable, Equatable, Identifiable {
    public var id: URL { url }
    public let url: URL
    /// EXIF 原文（例 "2026:04:13 04:52:50"）。EXIF なしは空文字
    public let datetimeRaw: String
    /// OffsetTimeOriginal → OffsetTime のフォールバック順（例 "-08:00"）
    public let offsetStr: String?
    /// datetimeRaw + offsetStr から求めた UTC（offsetStr がなければ nil）
    public let datetime: Date?
    public let hasGps: Bool

    public init(url: URL, datetimeRaw: String, offsetStr: String?, datetime: Date?, hasGps: Bool) {
        self.url = url
        self.datetimeRaw = datetimeRaw
        self.offsetStr = offsetStr
        self.datetime = datetime
        self.hasGps = hasGps
    }
}

// MARK: - マッチング

public enum MatchStatus: Sendable, Equatable {
    case pending, ok, done, warning, skip, error
}

public struct MatchedPoint: Sendable, Equatable {
    public let point: GpxPoint
    public let diffSec: TimeInterval

    public init(point: GpxPoint, diffSec: TimeInterval) {
        self.point = point
        self.diffSec = diffSec
    }
}

public struct MatchResult: Sendable, Equatable, Identifiable {
    public var id: URL { photo.url }
    public let photo: PhotoItem
    public let utcTime: Date?
    /// 書き込み後に done / error へ更新するため var
    public var status: MatchStatus
    public var statusLabel: String
    public let match: MatchedPoint?

    public init(photo: PhotoItem, utcTime: Date?, status: MatchStatus, statusLabel: String, match: MatchedPoint?) {
        self.photo = photo
        self.utcTime = utcTime
        self.status = status
        self.statusLabel = statusLabel
        self.match = match
    }

    /// GPX 未読込などの初期状態
    public static func pending(_ photo: PhotoItem) -> MatchResult {
        MatchResult(photo: photo, utcTime: nil, status: .pending, statusLabel: "—", match: nil)
    }
}

public enum TzMode: String, Sendable {
    case auto, manual
}

public struct MatchOptions: Sendable, Equatable {
    /// 秒。既定 3600
    public var maxTimeDiff: TimeInterval
    public var overwriteGps: Bool
    public var tzMode: TzMode
    public var tzOffsetHours: Double
    public var stationaryGapFill: Bool
    /// メートル。既定 50
    public var stationaryGapMaxDist: Double

    public init(
        maxTimeDiff: TimeInterval = 3600,
        overwriteGps: Bool = false,
        tzMode: TzMode = .auto,
        tzOffsetHours: Double = -8,
        stationaryGapFill: Bool = true,
        stationaryGapMaxDist: Double = 50
    ) {
        self.maxTimeDiff = maxTimeDiff
        self.overwriteGps = overwriteGps
        self.tzMode = tzMode
        self.tzOffsetHours = tzOffsetHours
        self.stationaryGapFill = stationaryGapFill
        self.stationaryGapMaxDist = stationaryGapMaxDist
    }
}

// MARK: - 書き込み

/// 座標から求めた現地時刻への書き換え内容
public struct LocalTimeRewrite: Sendable, Equatable {
    /// "±HH:MM"
    public let offsetStr: String
    /// exiftool 形式 "YYYY:MM:DD HH:MM:SS"
    public let localDto: String

    public init(offsetStr: String, localDto: String) {
        self.offsetStr = offsetStr
        self.localDto = localDto
    }
}

public struct GpsWriteRequest: Sendable {
    public let url: URL
    public let lat: Double
    public let lon: Double
    public let ele: Double?
    /// nil なら DateTimeOriginal / Offset 系の書き換えをスキップ（GPS のみ書く）
    public let localRewrite: LocalTimeRewrite?

    public init(url: URL, lat: Double, lon: Double, ele: Double?, localRewrite: LocalTimeRewrite?) {
        self.url = url
        self.lat = lat
        self.lon = lon
        self.ele = ele
        self.localRewrite = localRewrite
    }
}
