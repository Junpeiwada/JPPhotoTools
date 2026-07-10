import Foundation
import SwiftTimeZoneLookup

/// 座標 → IANA タイムゾーン → 撮影時点のオフセット / 現地時刻文字列（geo-tz 置換）。
/// タイムゾーン境界データの初期化コストがあるため、インスタンスを 1 つ保持して使い回す。
///
/// SwiftTimeZoneLookup の内部実装（ZoneDetect データベースへの OpaquePointer 保持）は
/// Sendable 宣言を持たないが、公開 API（lookup/simple）はデータベースを読み取るのみで
/// 内部可変状態を書き換えないため、複数スレッドからの同時呼び出しは安全と判断する
/// （@unchecked Sendable）。
public final class TimeZoneResolver: @unchecked Sendable {
    private let lookup: SwiftTimeZoneLookup

    public init() throws {
        lookup = try SwiftTimeZoneLookup()
    }

    /// 座標からタイムゾーンを引き、utcTime 時点のオフセットと現地時刻を返す。
    /// タイムゾーンが引けない座標（公海など）は nil（呼び出し側は日時書き換えをスキップ）
    public func resolve(lat: Double, lon: Double, utcTime: Date) -> LocalTimeRewrite? {
        guard let identifier = lookup.simple(latitude: Float(lat), longitude: Float(lon)) else {
            return nil
        }
        guard let timeZone = TimeZone(identifier: identifier) else {
            return nil
        }

        let offsetSeconds = timeZone.secondsFromGMT(for: utcTime)
        let offsetStr = Self.formatOffset(seconds: offsetSeconds)

        let localDate = utcTime.addingTimeInterval(TimeInterval(offsetSeconds))
        let localDto = DateFormatter.exifLocalUTC.string(from: localDate)

        return LocalTimeRewrite(offsetStr: offsetStr, localDto: localDto)
    }

    private static func formatOffset(seconds: Int) -> String {
        let sign = seconds >= 0 ? "+" : "-"
        let absMinutes = abs(seconds) / 60
        let hh = absMinutes / 60
        let mm = absMinutes % 60
        return String(format: "%@%02d:%02d", sign, hh, mm)
    }
}

extension DateFormatter {
    /// 現地時刻文字列を "yyyy:MM:dd HH:mm:ss" 形式で生成する（exiftool 形式）。
    /// localDate は既に utcTime + offset 済みの値なので、フォーマッタ自体は UTC 固定で
    /// 「壁時計としての文字列化」だけを行う
    fileprivate static let exifLocalUTC: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f
    }()
}
