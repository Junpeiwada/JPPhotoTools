import Foundation

/// GPX 1.1 の <trkpt> をストリーミングパースし、UTC 昇順の GpxData を返す。
public enum GpxParser {
    /// lat / lon / <time> のいずれかが欠けた点は捨てる。<ele> は任意。
    public static func parse(contentsOf url: URL) throws -> GpxData {
        let data = try Data(contentsOf: url)
        return parse(data: data)
    }

    public static func parse(data: Data) -> GpxData {
        let delegate = GpxParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()

        var points = delegate.points
        points.sort { $0.time < $1.time }

        return GpxData(
            points: points,
            dateMin: points.first?.time,
            dateMax: points.last?.time
        )
    }

    /// 複数 GPX をマージして時刻昇順にソート
    public static func merge(_ dataList: [GpxData]) -> GpxData {
        var allPoints = dataList.flatMap(\.points)
        allPoints.sort { $0.time < $1.time }

        return GpxData(
            points: allPoints,
            dateMin: allPoints.first?.time,
            dateMax: allPoints.last?.time
        )
    }

    /// 例: "624,906 ポイント / 2026-04-08 〜 2026-04-18"（ポイントなしは "ポイントなし"）
    public static func summary(_ data: GpxData) -> String {
        guard !data.points.isEmpty, let dateMin = data.dateMin, let dateMax = data.dateMax else {
            return "ポイントなし"
        }
        let count = NumberFormatter.gpxPointCount.string(from: NSNumber(value: data.points.count)) ?? "\(data.points.count)"
        let minStr = DateFormatter.gpxSummaryDay.string(from: dateMin)
        let maxStr = DateFormatter.gpxSummaryDay.string(from: dateMax)
        return "\(count) ポイント / \(minStr) 〜 \(maxStr)"
    }
}

private final class GpxParserDelegate: NSObject, XMLParserDelegate {
    var points: [GpxPoint] = []

    private var inTrkpt = false
    /// <trkpt> 直下の <time> または <ele> の中にいる間だけ true（<extensions> 等の孫要素を無視する）
    private var inTextElement = false
    private var trkptDepth = 0
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentTime: Date?
    private var currentEle: Double?

    private var currentElementText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "trkpt" {
            inTrkpt = true
            trkptDepth = 0
            currentLat = Double(attributeDict["lat"] ?? "")
            currentLon = Double(attributeDict["lon"] ?? "")
            currentTime = nil
            currentEle = nil
            return
        }
        guard inTrkpt else { return }
        if trkptDepth == 0, elementName == "time" || elementName == "ele" {
            inTextElement = true
            currentElementText = ""
        }
        trkptDepth += 1
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inTextElement else { return }
        currentElementText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard inTrkpt else { return }

        if elementName == "trkpt" {
            inTrkpt = false
            inTextElement = false
            if let lat = currentLat, let lon = currentLon, let time = currentTime {
                points.append(GpxPoint(lat: lat, lon: lon, ele: currentEle, time: time))
            }
            currentLat = nil
            currentLon = nil
            currentTime = nil
            currentEle = nil
            return
        }

        trkptDepth -= 1
        if trkptDepth == 0, inTextElement {
            let text = currentElementText.trimmingCharacters(in: .whitespacesAndNewlines)
            if elementName == "time" {
                currentTime = GpxDateParsing.parseISO8601(text)
            } else if elementName == "ele" {
                currentEle = Double(text)
            }
            inTextElement = false
            currentElementText = ""
        }
    }
}

enum GpxDateParsing {
    // タイムゾーンあり（Z / ±HH:MM）とフラクショナル秒ありの両方に対応する。
    // ISO8601DateFormatter / NumberFormatter / DateFormatter は Sendable 非準拠だが、
    // 生成後は formatOptions / dateFormat 等を変更せず読み取り専用（date(from:)/string(from:)）
    // でしか使わないため、並行アクセスは安全と判断して nonisolated(unsafe) を付与する。
    nonisolated(unsafe) private static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let standard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseISO8601(_ text: String) -> Date? {
        if let d = standard.date(from: text) {
            return d
        }
        return withFractional.date(from: text)
    }
}

extension NumberFormatter {
    fileprivate static let gpxPointCount: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US_POSIX")
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        return f
    }()
}

extension DateFormatter {
    fileprivate static let gpxSummaryDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
