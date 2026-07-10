import Testing
import Foundation
@testable import GeoTaggerCore

// MARK: - テスト用ヘルパー

private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = day
    comps.hour = hour
    comps.minute = minute
    comps.second = second
    comps.timeZone = TimeZone(identifier: "UTC")
    return Calendar(identifier: .gregorian).date(from: comps)!
}

private func gpxPoint(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0, lat: Double = 35.0, lon: Double = 135.0, ele: Double? = nil) -> GpxPoint {
    GpxPoint(lat: lat, lon: lon, ele: ele, time: utc(year, month, day, hour, minute, second))
}

private func photo(
    datetimeRaw: String = "2026:04:13 04:52:50",
    offsetStr: String? = "-08:00",
    datetime: Date? = nil,
    hasGps: Bool = false,
    name: String = "test.jpg"
) -> PhotoItem {
    let resolvedDatetime = datetime ?? ExifReader.parseExifDate(datetimeRaw, offsetStr: offsetStr)
    return PhotoItem(
        url: URL(fileURLWithPath: "/tmp/\(name)"),
        datetimeRaw: datetimeRaw,
        offsetStr: offsetStr,
        datetime: resolvedDatetime,
        hasGps: hasGps
    )
}

// MARK: - Matcher: fmtDiff

@Test func fmtDiffSecondsUnder60() {
    #expect(Matcher.fmtDiff(0) == "0秒")
    #expect(Matcher.fmtDiff(1) == "1秒")
    #expect(Matcher.fmtDiff(59) == "59秒")
    #expect(Matcher.fmtDiff(59.6) == "60秒") // 四捨五入で境界超え
}

@Test func fmtDiffMinutesUnder3600() {
    #expect(Matcher.fmtDiff(60) == "1分")
    #expect(Matcher.fmtDiff(90) == "2分") // 1.5分 → 四捨五入で2分
    #expect(Matcher.fmtDiff(3599) == "60分")
}

@Test func fmtDiffHoursOver3600() {
    #expect(Matcher.fmtDiff(3600) == "1.0時間")
    #expect(Matcher.fmtDiff(5400) == "1.5時間")
    #expect(Matcher.fmtDiff(7200) == "2.0時間")
}

// MARK: - Matcher: haversineMeters

@Test func haversineZeroDistance() {
    let d = Matcher.haversineMeters(lat1: 35.0, lon1: 135.0, lat2: 35.0, lon2: 135.0)
    #expect(d == 0)
}

@Test func haversineKnownDistance() {
    // 東京駅(35.681236, 139.767125) と新大阪駅(34.733611, 135.500067) 間は概ね 400km
    let d = Matcher.haversineMeters(lat1: 35.681236, lon1: 139.767125, lat2: 34.733611, lon2: 135.500067)
    #expect(d > 390_000 && d < 410_000)
}

// MARK: - Matcher: binarySearchNearest

@Test func binarySearchNearestEmptyReturnsNil() {
    #expect(Matcher.binarySearchNearest([], target: utc(2026, 4, 13, 12, 0)) == nil)
}

@Test func binarySearchNearestBeforeFirstPoint() {
    let points = [
        gpxPoint(2026, 4, 13, 12, 0),
        gpxPoint(2026, 4, 13, 13, 0),
    ]
    let target = utc(2026, 4, 13, 11, 0)
    let result = Matcher.binarySearchNearest(points, target: target)
    #expect(result?.time == points[0].time)
}

@Test func binarySearchNearestAfterLastPoint() {
    let points = [
        gpxPoint(2026, 4, 13, 12, 0),
        gpxPoint(2026, 4, 13, 13, 0),
    ]
    let target = utc(2026, 4, 13, 14, 0)
    let result = Matcher.binarySearchNearest(points, target: target)
    #expect(result?.time == points[1].time)
}

@Test func binarySearchNearestPicksCloserPrevious() {
    let points = [
        gpxPoint(2026, 4, 13, 12, 0, 0),
        gpxPoint(2026, 4, 13, 12, 10, 0),
    ]
    // target が 12:00 に近い（12:03 → 前3分 / 後7分）
    let target = utc(2026, 4, 13, 12, 3, 0)
    let result = Matcher.binarySearchNearest(points, target: target)
    #expect(result?.time == points[0].time)
}

@Test func binarySearchNearestPicksCloserNext() {
    let points = [
        gpxPoint(2026, 4, 13, 12, 0, 0),
        gpxPoint(2026, 4, 13, 12, 10, 0),
    ]
    // target が 12:10 に近い（12:07 → 前7分 / 後3分）
    let target = utc(2026, 4, 13, 12, 7, 0)
    let result = Matcher.binarySearchNearest(points, target: target)
    #expect(result?.time == points[1].time)
}

@Test func binarySearchNearestExactBoundaryPrefersLaterIndex() {
    // 前後が等距離の場合、元実装の `dPrev < dLo`（同値では更新しない）に合わせて後方(lo)を採用する
    let points = [
        gpxPoint(2026, 4, 13, 12, 0, 0),
        gpxPoint(2026, 4, 13, 12, 10, 0),
    ]
    let target = utc(2026, 4, 13, 12, 5, 0) // 前後ちょうど5分ずつ
    let result = Matcher.binarySearchNearest(points, target: target)
    #expect(result?.time == points[1].time)
}

// MARK: - Matcher: findStationaryGap

@Test func findStationaryGapSuccessWithinDistance() {
    let points = [
        gpxPoint(2026, 4, 13, 12, 0, lat: 35.0, lon: 135.0),
        gpxPoint(2026, 4, 13, 14, 0, lat: 35.0001, lon: 135.0), // 約11m
    ]
    let target = utc(2026, 4, 13, 13, 0) // 前後1時間ずつ、静止判定
    let result = Matcher.findStationaryGap(points, target: target, maxDistMeters: 50)
    #expect(result?.time == points[0].time)
}

@Test func findStationaryGapFailsWhenTooFar() {
    let points = [
        gpxPoint(2026, 4, 13, 12, 0, lat: 35.0, lon: 135.0),
        gpxPoint(2026, 4, 13, 14, 0, lat: 36.0, lon: 135.0), // 遠い
    ]
    let target = utc(2026, 4, 13, 13, 0)
    let result = Matcher.findStationaryGap(points, target: target, maxDistMeters: 50)
    #expect(result == nil)
}

@Test func findStationaryGapFailsWithSinglePoint() {
    let points = [gpxPoint(2026, 4, 13, 12, 0)]
    let result = Matcher.findStationaryGap(points, target: utc(2026, 4, 13, 12, 0), maxDistMeters: 50)
    #expect(result == nil)
}

@Test func findStationaryGapFailsWhenTargetBeforeAllPoints() {
    let points = [
        gpxPoint(2026, 4, 13, 12, 0),
        gpxPoint(2026, 4, 13, 13, 0),
    ]
    let result = Matcher.findStationaryGap(points, target: utc(2026, 4, 13, 11, 0), maxDistMeters: 50)
    #expect(result == nil)
}

@Test func findStationaryGapTargetAfterAllPointsUsesLastPairBoundary() {
    // 元実装 matcher.ts の findStationaryGap は二分探索の hi 上限により、target が
    // 全ポイントより後でも lo は points.length-1 に留まる（lo >= points.length には
    // ならない）ため、最後の2点ペアで静止判定してしまう。この癖も含めて 1:1 移植する。
    let points = [
        gpxPoint(2026, 4, 13, 12, 0, lat: 35.0, lon: 135.0),
        gpxPoint(2026, 4, 13, 13, 0, lat: 35.0001, lon: 135.0), // 約11m、静止
    ]
    let result = Matcher.findStationaryGap(points, target: utc(2026, 4, 13, 14, 0), maxDistMeters: 50)
    #expect(result?.time == points[0].time)
}

// MARK: - Matcher: manualUtcTime

@Test func manualUtcTimeAppliesNegativeOffset() {
    // "2026:04:13 04:52:50" をローカル -08:00 とみなすと UTC は 12:52:50
    let result = Matcher.manualUtcTime(datetimeRaw: "2026:04:13 04:52:50", tzOffsetHours: -8)
    #expect(result == utc(2026, 4, 13, 12, 52, 50))
}

@Test func manualUtcTimeAppliesPositiveOffset() {
    // JST +9:00 のローカル 13:00:00 → UTC 04:00:00
    let result = Matcher.manualUtcTime(datetimeRaw: "2026:04:13 13:00:00", tzOffsetHours: 9)
    #expect(result == utc(2026, 4, 13, 4, 0, 0))
}

@Test func manualUtcTimeAppliesFractionalOffset() {
    // インド標準時 +5.5 時間
    let result = Matcher.manualUtcTime(datetimeRaw: "2026:04:13 10:30:00", tzOffsetHours: 5.5)
    #expect(result == utc(2026, 4, 13, 5, 0, 0))
}

@Test func manualUtcTimeInvalidRawReturnsNil() {
    let result = Matcher.manualUtcTime(datetimeRaw: "not-a-date", tzOffsetHours: 0)
    #expect(result == nil)
}

// MARK: - Matcher: matchAll 分岐網羅

@Test func matchAllErrorWhenNoExifAtAll() {
    // offsetStr なし かつ datetimeRaw も空 → EXIF なし
    let p = photo(datetimeRaw: "", offsetStr: nil, datetime: nil)
    let results = Matcher.matchAll(gpxPoints: [], photos: [p], options: MatchOptions())
    #expect(results[0].status == .error)
    #expect(results[0].statusLabel == "⚠ EXIF なし")
    #expect(results[0].utcTime == nil)
}

@Test func matchAllErrorWhenUtcTimeUnresolvable() {
    // offsetStr ありだが datetime が nil になるケース（不正な日時文字列）
    let p = PhotoItem(url: URL(fileURLWithPath: "/tmp/a.jpg"), datetimeRaw: "invalid", offsetStr: "-08:00", datetime: nil, hasGps: false)
    let results = Matcher.matchAll(gpxPoints: [], photos: [p], options: MatchOptions())
    #expect(results[0].status == .error)
    #expect(results[0].statusLabel == "⚠ 時刻不明")
}

@Test func matchAllSkipsWhenHasGpsAndNotOverwrite() {
    let p = photo(hasGps: true)
    var opts = MatchOptions()
    opts.overwriteGps = false
    let results = Matcher.matchAll(gpxPoints: [gpxPoint(2026, 4, 13, 12, 0)], photos: [p], options: opts)
    #expect(results[0].status == .skip)
    #expect(results[0].statusLabel == "— スキップ")
    #expect(results[0].match == nil)
}

@Test func matchAllProceedsWhenHasGpsAndOverwrite() {
    let dt = utc(2026, 4, 13, 12, 52, 50)
    let p = photo(datetime: dt, hasGps: true)
    var opts = MatchOptions()
    opts.overwriteGps = true
    let results = Matcher.matchAll(gpxPoints: [gpxPoint(2026, 4, 13, 12, 52, 50)], photos: [p], options: opts)
    #expect(results[0].status == .ok)
    #expect(results[0].statusLabel == "✓ マッチ済み")
}

@Test func matchAllWarningWhenNoGpxPoints() {
    let p = photo(datetime: utc(2026, 4, 13, 12, 0))
    let results = Matcher.matchAll(gpxPoints: [], photos: [p], options: MatchOptions())
    #expect(results[0].status == .warning)
    #expect(results[0].statusLabel == "⚠ GPXなし")
}

@Test func matchAllOkWithinThreshold() {
    let dt = utc(2026, 4, 13, 12, 0, 0)
    let p = photo(datetime: dt)
    let points = [gpxPoint(2026, 4, 13, 12, 5, 0)] // 5分差
    var opts = MatchOptions()
    opts.maxTimeDiff = 3600
    let results = Matcher.matchAll(gpxPoints: points, photos: [p], options: opts)
    #expect(results[0].status == .ok)
    #expect(results[0].statusLabel == "✓ マッチ済み")
    #expect(results[0].match?.diffSec == 300)
}

@Test func matchAllStationaryGapFillSucceeds() {
    let dt = utc(2026, 4, 13, 13, 0, 0)
    let p = photo(datetime: dt)
    let points = [
        gpxPoint(2026, 4, 13, 10, 0, lat: 35.0, lon: 135.0),
        gpxPoint(2026, 4, 13, 16, 0, lat: 35.0001, lon: 135.0), // 約11m、静止
    ]
    var opts = MatchOptions()
    opts.maxTimeDiff = 3600
    opts.stationaryGapFill = true
    opts.stationaryGapMaxDist = 50
    let results = Matcher.matchAll(gpxPoints: points, photos: [p], options: opts)
    #expect(results[0].status == .ok)
    #expect(results[0].statusLabel == "✓ 静止補完")
    #expect(results[0].match?.point.time == points[0].time)
}

@Test func matchAllStationaryGapFillFailsFallsBackToWarning() {
    let dt = utc(2026, 4, 13, 13, 0, 0)
    let p = photo(datetime: dt)
    let points = [
        gpxPoint(2026, 4, 13, 10, 0, lat: 35.0, lon: 135.0),
        gpxPoint(2026, 4, 13, 16, 0, lat: 36.0, lon: 135.0), // 遠い、静止と判定されない
    ]
    var opts = MatchOptions()
    opts.maxTimeDiff = 3600
    opts.stationaryGapFill = true
    opts.stationaryGapMaxDist = 50
    let results = Matcher.matchAll(gpxPoints: points, photos: [p], options: opts)
    #expect(results[0].status == .warning)
    #expect(results[0].statusLabel.hasPrefix("⚠ 時間差"))
}

@Test func matchAllStationaryGapFillDisabledGoesStraightToWarning() {
    let dt = utc(2026, 4, 13, 13, 0, 0)
    let p = photo(datetime: dt)
    let points = [
        gpxPoint(2026, 4, 13, 10, 0, lat: 35.0, lon: 135.0),
        gpxPoint(2026, 4, 13, 16, 0, lat: 35.0001, lon: 135.0), // 静止条件は満たすが無効化
    ]
    var opts = MatchOptions()
    opts.maxTimeDiff = 3600
    opts.stationaryGapFill = false
    let results = Matcher.matchAll(gpxPoints: points, photos: [p], options: opts)
    #expect(results[0].status == .warning)
    #expect(results[0].statusLabel.hasPrefix("⚠ 時間差"))
}

@Test func matchAllManualModeAppliesToAllFilesRegardlessOfOffsetStr() {
    // 手動モードでは offsetStr の有無に関わらず全ファイルへ手動オフセットを適用する
    let withOffset = photo(datetimeRaw: "2026:04:13 04:52:50", offsetStr: "-08:00", name: "with.jpg")
    let withoutOffset = photo(datetimeRaw: "2026:04:13 04:52:50", offsetStr: nil, datetime: nil, name: "without.jpg")

    var opts = MatchOptions()
    opts.tzMode = .manual
    opts.tzOffsetHours = -8

    let results = Matcher.matchAll(gpxPoints: [], photos: [withOffset, withoutOffset], options: opts)
    // 両方とも同じ手動オフセットで UTC 変換されるため utcTime は一致するはず
    #expect(results[0].utcTime == results[1].utcTime)
    #expect(results[0].utcTime == utc(2026, 4, 13, 12, 52, 50))
}

@Test func matchAllAutoModeUsesOffsetStrWhenPresent() {
    // auto モードかつ offsetStr あり → datetime（EXIF計算済みUTC）をそのまま使う
    let dt = utc(2026, 4, 13, 12, 52, 50)
    let p = photo(datetimeRaw: "2026:04:13 04:52:50", offsetStr: "-08:00", datetime: dt)
    var opts = MatchOptions()
    opts.tzMode = .auto
    let results = Matcher.matchAll(gpxPoints: [], photos: [p], options: opts)
    #expect(results[0].utcTime == dt)
    #expect(results[0].status == .warning) // GPX 未読込
}

// MARK: - GpxParser

private let sampleGpx = """
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="test">
  <trk>
    <trkseg>
      <trkpt lat="35.681236" lon="139.767125">
        <ele>10.5</ele>
        <time>2026-04-13T04:00:00Z</time>
      </trkpt>
      <trkpt lat="35.682000" lon="139.768000">
        <ele>11.0</ele>
        <time>2026-04-13T04:05:00Z</time>
      </trkpt>
    </trkseg>
  </trk>
</gpx>
"""

@Test func gpxParserParsesBasicPoints() {
    let data = GpxParser.parse(data: Data(sampleGpx.utf8))
    #expect(data.points.count == 2)
    #expect(data.points[0].lat == 35.681236)
    #expect(data.points[0].lon == 139.767125)
    #expect(data.points[0].ele == 10.5)
    #expect(data.dateMin == data.points[0].time)
    #expect(data.dateMax == data.points[1].time)
}

@Test func gpxParserSortsByTimeAscending() {
    let unordered = """
    <?xml version="1.0"?>
    <gpx><trk><trkseg>
      <trkpt lat="1" lon="1"><time>2026-04-13T05:00:00Z</time></trkpt>
      <trkpt lat="2" lon="2"><time>2026-04-13T03:00:00Z</time></trkpt>
      <trkpt lat="3" lon="3"><time>2026-04-13T04:00:00Z</time></trkpt>
    </trkseg></trk></gpx>
    """
    let data = GpxParser.parse(data: Data(unordered.utf8))
    #expect(data.points.map(\.lat) == [2, 3, 1])
}

@Test func gpxParserDropsPointsMissingLatLonOrTime() {
    let malformed = """
    <?xml version="1.0"?>
    <gpx><trk><trkseg>
      <trkpt lat="1" lon="1"><time>2026-04-13T05:00:00Z</time></trkpt>
      <trkpt lon="2"><time>2026-04-13T03:00:00Z</time></trkpt>
      <trkpt lat="3" lon="3"></trkpt>
    </trkseg></trk></gpx>
    """
    let data = GpxParser.parse(data: Data(malformed.utf8))
    #expect(data.points.count == 1)
    #expect(data.points[0].lat == 1)
}

@Test func gpxParserEleOptional() {
    let noEle = """
    <?xml version="1.0"?>
    <gpx><trk><trkseg>
      <trkpt lat="1" lon="1"><time>2026-04-13T05:00:00Z</time></trkpt>
    </trkseg></trk></gpx>
    """
    let data = GpxParser.parse(data: Data(noEle.utf8))
    #expect(data.points.count == 1)
    #expect(data.points[0].ele == nil)
}

@Test func gpxParserHandlesMultipleTrksegs() {
    let multiSeg = """
    <?xml version="1.0"?>
    <gpx><trk>
      <trkseg><trkpt lat="1" lon="1"><time>2026-04-13T04:00:00Z</time></trkpt></trkseg>
      <trkseg><trkpt lat="2" lon="2"><time>2026-04-13T05:00:00Z</time></trkpt></trkseg>
    </trk></gpx>
    """
    let data = GpxParser.parse(data: Data(multiSeg.utf8))
    #expect(data.points.count == 2)
}

@Test func gpxParserMergeCombinesAndSorts() {
    let a = GpxData(points: [gpxPoint(2026, 4, 13, 10, 0)], dateMin: nil, dateMax: nil)
    let b = GpxData(points: [gpxPoint(2026, 4, 13, 8, 0)], dateMin: nil, dateMax: nil)
    let merged = GpxParser.merge([a, b])
    #expect(merged.points.count == 2)
    #expect(merged.points[0].time == b.points[0].time)
    #expect(merged.dateMin == b.points[0].time)
    #expect(merged.dateMax == a.points[0].time)
}

@Test func gpxParserSummaryEmpty() {
    let empty = GpxData(points: [], dateMin: nil, dateMax: nil)
    #expect(GpxParser.summary(empty) == "ポイントなし")
}

@Test func gpxParserSummaryFormatsDatesAndCount() {
    var points: [GpxPoint] = []
    for i in 0..<1234 {
        points.append(gpxPoint(2026, 4, 8, 0, 0, i % 60))
    }
    let data = GpxData(points: points, dateMin: utc(2026, 4, 8, 0, 0, 0), dateMax: utc(2026, 4, 18, 0, 0, 0))
    let summary = GpxParser.summary(data)
    #expect(summary == "1,234 ポイント / 2026-04-08 〜 2026-04-18")
}

// MARK: - ExifReader: parseExifDate

@Test func parseExifDateValidWithNegativeOffset() {
    let d = ExifReader.parseExifDate("2026:04:13 04:52:50", offsetStr: "-08:00")
    #expect(d == utc(2026, 4, 13, 12, 52, 50))
}

@Test func parseExifDateValidWithPositiveOffset() {
    let d = ExifReader.parseExifDate("2026:04:13 13:00:00", offsetStr: "+09:00")
    #expect(d == utc(2026, 4, 13, 4, 0, 0))
}

@Test func parseExifDateNilWhenNoOffset() {
    let d = ExifReader.parseExifDate("2026:04:13 04:52:50", offsetStr: nil)
    #expect(d == nil)
}

@Test func parseExifDateNilWhenEmptyRaw() {
    let d = ExifReader.parseExifDate("", offsetStr: "-08:00")
    #expect(d == nil)
}

@Test func parseExifDateNilWhenMalformed() {
    let d = ExifReader.parseExifDate("not-a-date", offsetStr: "-08:00")
    #expect(d == nil)
}

// MARK: - ExifReader: listJpegs

@Test func listJpegsFiltersAndSortsCaseInsensitive() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let names = ["b.JPG", "a.jpg", "c.jpeg", "not-image.png", "d.JPEG"]
    for name in names {
        FileManager.default.createFile(atPath: tmpDir.appendingPathComponent(name).path, contents: Data())
    }
    // サブディレクトリは無視されること
    try FileManager.default.createDirectory(at: tmpDir.appendingPathComponent("sub.jpg"), withIntermediateDirectories: true)

    let result = ExifReader.listJpegs(in: tmpDir)
    #expect(result.map(\.lastPathComponent) == ["a.jpg", "b.JPG", "c.jpeg", "d.JPEG"])
}

// MARK: - ExifReader / GpsWriter 往復

private func makeTestJpeg(at url: URL, exif: [String: Any] = [:], gps: [String: Any] = [:]) throws {
    let width = 4, height = 4
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw TestSetupError.contextCreationFailed
    }
    ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let cgImage = ctx.makeImage() else { throw TestSetupError.imageCreationFailed }

    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
        throw TestSetupError.destinationCreationFailed
    }
    var properties: [String: Any] = [:]
    if !exif.isEmpty {
        properties[kCGImagePropertyExifDictionary as String] = exif
    }
    if !gps.isEmpty {
        properties[kCGImagePropertyGPSDictionary as String] = gps
    }
    CGImageDestinationAddImage(dest, cgImage, properties as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { throw TestSetupError.finalizeFailed }
}

private enum TestSetupError: Error {
    case contextCreationFailed, imageCreationFailed, destinationCreationFailed, finalizeFailed
}

import ImageIO
import CoreGraphics

@Test func exifReaderReadsDateTimeOffsetAndGps() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }
    let url = tmpDir.appendingPathComponent("test.jpg")

    try makeTestJpeg(
        at: url,
        exif: ["DateTimeOriginal": "2026:04:13 04:52:50", "OffsetTimeOriginal": "-08:00"],
        gps: ["Latitude": 35.0, "Longitude": 135.0]
    )

    let item = ExifReader.readPhoto(at: url)
    #expect(item.datetimeRaw == "2026:04:13 04:52:50")
    #expect(item.offsetStr == "-08:00")
    #expect(item.datetime == utc(2026, 4, 13, 12, 52, 50))
    #expect(item.hasGps == true)
}

@Test func exifReaderFallsBackToOffsetTimeWhenOriginalMissing() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }
    let url = tmpDir.appendingPathComponent("test.jpg")

    try makeTestJpeg(
        at: url,
        exif: ["DateTimeOriginal": "2026:04:13 04:52:50", "OffsetTime": "-07:00"]
    )

    let item = ExifReader.readPhoto(at: url)
    #expect(item.offsetStr == "-07:00")
    #expect(item.datetime == utc(2026, 4, 13, 11, 52, 50))
    #expect(item.hasGps == false)
}

@Test func exifReaderNoExifReturnsEmptyRaw() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }
    let url = tmpDir.appendingPathComponent("test.jpg")

    try makeTestJpeg(at: url)

    let item = ExifReader.readPhoto(at: url)
    #expect(item.datetimeRaw == "")
    #expect(item.offsetStr == nil)
    #expect(item.datetime == nil)
    #expect(item.hasGps == false)
}

@Test(.enabled(if: GpsWriter.detectExiftool() != nil, "exiftool が見つからないためスキップ"))
func gpsWriterRoundTripWritesLatLonAndAltitude() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }
    let url = tmpDir.appendingPathComponent("test.jpg")

    try makeTestJpeg(at: url, exif: ["DateTimeOriginal": "2026:04:13 04:52:50"])

    let request = GpsWriteRequest(url: url, lat: 35.681236, lon: -139.767125, ele: 123.4, localRewrite: nil)
    try GpsWriter.write(request)

    let item = ExifReader.readPhoto(at: url)
    #expect(item.hasGps == true)

    // GPS の生値も確認（Ref を考慮した符号付き値で読み戻す）
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] else {
        Issue.record("GPS 辞書が読み取れません")
        return
    }
    let lat = gps[kCGImagePropertyGPSLatitude] as? Double
    let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String
    let lon = gps[kCGImagePropertyGPSLongitude] as? Double
    let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String
    let alt = gps[kCGImagePropertyGPSAltitude] as? Double
    let altRef = gps[kCGImagePropertyGPSAltitudeRef] as? Int

    #expect(lat != nil && abs(lat! - 35.681236) < 0.00001)
    #expect(latRef == "N")
    #expect(lon != nil && abs(lon! - 139.767125) < 0.00001)
    #expect(lonRef == "W")
    #expect(alt != nil && abs(alt! - 123.4) < 0.01)
    #expect(altRef == 0)
}

@Test(.enabled(if: GpsWriter.detectExiftool() != nil, "exiftool が見つからないためスキップ"))
func gpsWriterRoundTripOmitsAltitudeWhenNil() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }
    let url = tmpDir.appendingPathComponent("test.jpg")

    try makeTestJpeg(at: url)

    let request = GpsWriteRequest(url: url, lat: -35.0, lon: 135.0, ele: nil, localRewrite: nil)
    try GpsWriter.write(request)

    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] else {
        Issue.record("GPS 辞書が読み取れません")
        return
    }
    #expect(gps[kCGImagePropertyGPSLatitudeRef] as? String == "S")
    #expect(gps[kCGImagePropertyGPSAltitude] == nil)
}

@Test(.enabled(if: GpsWriter.detectExiftool() != nil, "exiftool が見つからないためスキップ"))
func gpsWriterRoundTripWritesLocalRewrite() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }
    let url = tmpDir.appendingPathComponent("test.jpg")

    try makeTestJpeg(at: url, exif: ["DateTimeOriginal": "2026:04:13 04:52:50"])

    let rewrite = LocalTimeRewrite(offsetStr: "+09:00", localDto: "2026:04:13 21:52:50")
    let request = GpsWriteRequest(url: url, lat: 35.0, lon: 135.0, ele: nil, localRewrite: rewrite)
    try GpsWriter.write(request)

    let item = ExifReader.readPhoto(at: url)
    #expect(item.datetimeRaw == "2026:04:13 21:52:50")
    #expect(item.offsetStr == "+09:00")
}

@Test(.enabled(if: GpsWriter.detectExiftool() != nil, "exiftool が見つからないためスキップ"))
func gpsWriterPreservesExistingGpsWhenOverwriting() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }
    let url = tmpDir.appendingPathComponent("test.jpg")

    try makeTestJpeg(at: url, gps: ["Latitude": 10.0, "LatitudeRef": "N", "Longitude": 20.0, "LongitudeRef": "E"])

    let request = GpsWriteRequest(url: url, lat: 40.0, lon: -60.0, ele: nil, localRewrite: nil)
    try GpsWriter.write(request)

    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] else {
        Issue.record("GPS 辞書が読み取れません")
        return
    }
    let lat = gps[kCGImagePropertyGPSLatitude] as? Double
    #expect(lat != nil && abs(lat! - 40.0) < 0.00001)
    #expect(gps[kCGImagePropertyGPSLatitudeRef] as? String == "N")
    #expect(gps[kCGImagePropertyGPSLongitudeRef] as? String == "W")
}

// MARK: - TimeZoneResolver

@Test func timeZoneResolverKnownCoordinateTokyo() throws {
    let resolver = try TimeZoneResolver()
    // 東京駅付近、UTC のある夏の日時（DST の影響を受けない日本は常に +09:00）
    let rewrite = resolver.resolve(lat: 35.681236, lon: 139.767125, utcTime: utc(2026, 4, 13, 4, 52, 50))
    #expect(rewrite?.offsetStr == "+09:00")
    #expect(rewrite?.localDto == "2026:04:13 13:52:50")
}

@Test func timeZoneResolverKnownCoordinateUtahMDT() throws {
    let resolver = try TimeZoneResolver()
    // ユタ州(37.109, -113.554)、4月は MDT(-06:00)
    let rewrite = resolver.resolve(lat: 37.109, lon: -113.554, utcTime: utc(2026, 4, 13, 18, 0, 0))
    #expect(rewrite?.offsetStr == "-06:00")
}

@Test func timeZoneResolverKnownCoordinateNevadaPDT() throws {
    let resolver = try TimeZoneResolver()
    // ネバダ州(36.48, -114.52)、4月は PDT(-07:00)
    let rewrite = resolver.resolve(lat: 36.48, lon: -114.52, utcTime: utc(2026, 4, 13, 18, 0, 0))
    #expect(rewrite?.offsetStr == "-07:00")
}

@Test func timeZoneResolverCoversOpenOceanWithEtcGmtFallback() throws {
    let resolver = try TimeZoneResolver()
    // SwiftTimeZoneLookup の境界データは Etc/GMT 系のオフセット帯で海洋も含め全球を
    // カバーしているため、公海上でも UTC オフセットに基づく解決ができる
    // （geo-tz と異なり「陸地でないため nil」にはならない）
    let rewrite = resolver.resolve(lat: 0.0, lon: -160.0, utcTime: utc(2026, 4, 13, 12, 0, 0))
    #expect(rewrite?.offsetStr == "-11:00")
}

@Test func timeZoneResolverNilForOutOfRangeCoordinate() throws {
    let resolver = try TimeZoneResolver()
    // 有効な緯度経度の範囲外（データベース側でルックアップ不能）は nil を返す
    let rewrite = resolver.resolve(lat: 91.0, lon: 0.0, utcTime: utc(2026, 4, 13, 12, 0, 0))
    #expect(rewrite == nil)
}

// MARK: - GeoShutterLocator

@Test func geoShutterParsesSingleDateFilename() {
    let result = GeoShutterLocator.parseFilenameDates("GeoShutter_2026-04-13.gpx")
    #expect(result != nil)
    #expect(result?.start == utc(2026, 4, 13, 0, 0, 0))
    #expect(result?.end == utc(2026, 4, 13, 23, 59, 59))
}

@Test func geoShutterParsesRangeFilename() {
    let result = GeoShutterLocator.parseFilenameDates("GeoShutter_2026-04-13_2026-04-15.gpx")
    #expect(result?.start == utc(2026, 4, 13, 0, 0, 0))
    #expect(result?.end == utc(2026, 4, 15, 23, 59, 59))
}

@Test func geoShutterParsesFailsOnUnrelatedFilename() {
    #expect(GeoShutterLocator.parseFilenameDates("random.gpx") == nil)
}

@Test func geoShutterCandidatesFiltersWithinBuffer() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let names = [
        "GeoShutter_2026-04-13.gpx",       // 写真期間ちょうど
        "GeoShutter_2026-04-10.gpx",       // 写真開始の3日前（バッファ2日超え、除外）
        "GeoShutter_2026-04-12.gpx",       // 写真開始の1日前（バッファ内、含む）
        "GeoShutter_2026-05-01.gpx",       // 遠い未来（除外）
        "not-a-gpx.txt",                   // 拡張子違い（除外）
    ]
    for name in names {
        FileManager.default.createFile(atPath: tmpDir.appendingPathComponent(name).path, contents: Data())
    }

    let photoMin = utc(2026, 4, 13, 0, 0, 0)
    let photoMax = utc(2026, 4, 13, 23, 59, 59)
    let result = GeoShutterLocator.candidates(photoMinUTC: photoMin, photoMaxUTC: photoMax, in: tmpDir)
    let resultNames = Set(result.map(\.lastPathComponent))

    #expect(resultNames.contains("GeoShutter_2026-04-13.gpx"))
    #expect(resultNames.contains("GeoShutter_2026-04-12.gpx"))
    #expect(!resultNames.contains("GeoShutter_2026-04-10.gpx"))
    #expect(!resultNames.contains("GeoShutter_2026-05-01.gpx"))
    #expect(!resultNames.contains("not-a-gpx.txt"))
}

// MARK: - MatchOptions 既定値

@Test func matchOptionsDefaults() {
    let opts = MatchOptions()
    #expect(opts.maxTimeDiff == 3600)
    #expect(opts.overwriteGps == false)
    #expect(opts.tzMode == .auto)
    #expect(opts.tzOffsetHours == -8)
    #expect(opts.stationaryGapFill == true)
    #expect(opts.stationaryGapMaxDist == 50)
}

