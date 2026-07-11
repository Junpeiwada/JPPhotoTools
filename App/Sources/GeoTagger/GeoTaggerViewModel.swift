import Foundation
import SwiftUI
import GeoTaggerCore

/// GeoTagger タブの状態と操作。元 Electron 版 `app.ts` の状態遷移をそのまま踏襲する。
///
/// 設定（フォルダ・TZ・しきい値）は `UserDefaults` を `geoTagger` プレフィックスで直接読み書きする。
/// ViewModel は ObservableObject のため `@AppStorage` は使えず、ペイン寸法のみ View 側で
/// `@AppStorage` を使う（View 固有の見た目の状態なので自然な置き場所）。
@MainActor
final class GeoTaggerViewModel: ObservableObject {

    // MARK: - 設定キー

    private enum Keys {
        static let photoFolder = "geoTaggerPhotoFolder"
        static let tzMode = "geoTaggerTzMode"
        static let tzOffset = "geoTaggerTzOffset"
        static let overwriteGps = "geoTaggerOverwriteGps"
        static let maxTimeDiff = "geoTaggerMaxTimeDiff"
        static let gapFill = "geoTaggerGapFill"
        static let gapDist = "geoTaggerGapDist"
    }

    private enum Defaults {
        static let photoFolder = "/Users/junpeiwada/Documents/LightroomOutput"
        static let tzMode = TzMode.auto
        static let tzOffset: Double = -8
        static let overwriteGps = false
        static let maxTimeDiff: TimeInterval = 3600
        static let gapFill = true
        static let gapDist: Double = 50
    }

    // MARK: - 公開状態

    /// (GPX ファイルパス, パース結果) のリスト。追加順を維持する。
    @Published private(set) var loadedGpxFiles: [(url: URL, data: GpxData)] = []
    /// loadedGpxFiles をマージ・時刻ソートしたもの。空なら nil。
    @Published private(set) var mergedGpx: GpxData?

    @Published private(set) var photoFolder: URL?
    @Published private(set) var photoItems: [PhotoItem] = []
    @Published private(set) var matchResults: [MatchResult] = []
    @Published var selection: URL?

    @Published var busy: Bool = false
    /// (完了数, 総数)。0 件時は nil で非表示。
    @Published private(set) var loadProgress: (done: Int, total: Int)?
    /// GPX パース進捗 (完了数, 総数)。nil で非表示。GeoShutter 自動読み込みは数十ファイルに
    /// 及び数十秒かかりうるため、ボタン無効化だけでは「動いている」ことが伝わらない。
    @Published private(set) var gpxLoadProgress: (done: Int, total: Int)?
    @Published private(set) var applyProgress: (done: Int, total: Int, success: Int, failed: Int)?
    @Published private(set) var applySummary: String?

    // MARK: - 設定（UI から双方向バインドできるよう didSet で永続化 + 再マッチ）

    @Published var tzMode: TzMode {
        didSet {
            guard oldValue != tzMode else { return }
            UserDefaults.standard.set(tzMode.rawValue, forKey: Keys.tzMode)
            runPreview()
        }
    }
    @Published var tzOffsetHours: Double {
        didSet {
            guard oldValue != tzOffsetHours else { return }
            UserDefaults.standard.set(tzOffsetHours, forKey: Keys.tzOffset)
            runPreview()
        }
    }
    @Published var overwriteGps: Bool {
        didSet {
            guard oldValue != overwriteGps else { return }
            UserDefaults.standard.set(overwriteGps, forKey: Keys.overwriteGps)
            runPreview()
        }
    }
    @Published var maxTimeDiff: TimeInterval {
        didSet {
            guard oldValue != maxTimeDiff else { return }
            UserDefaults.standard.set(maxTimeDiff, forKey: Keys.maxTimeDiff)
            runPreview()
        }
    }
    @Published var stationaryGapFill: Bool {
        didSet {
            guard oldValue != stationaryGapFill else { return }
            UserDefaults.standard.set(stationaryGapFill, forKey: Keys.gapFill)
            runPreview()
        }
    }
    @Published var stationaryGapMaxDist: Double {
        didSet {
            guard oldValue != stationaryGapMaxDist else { return }
            UserDefaults.standard.set(stationaryGapMaxDist, forKey: Keys.gapDist)
            runPreview()
        }
    }

    /// TimeZoneResolver は init throws のため、初回付与時に一度だけ生成して使い回す。
    private var timeZoneResolver: TimeZoneResolver?
    private var didAutoLoadFolder = false

    // MARK: - 派生値

    var noOffsetCount: Int {
        photoItems.filter { $0.offsetStr == nil }.count
    }

    var okCount: Int {
        matchResults.filter { $0.status == .ok || $0.status == .done }.count
    }

    var warningCount: Int {
        matchResults.filter { $0.status == .warning }.count
    }

    var skipCount: Int {
        matchResults.filter { $0.status == .skip }.count
    }

    var canApply: Bool {
        !busy && matchResults.contains { $0.status == .ok }
    }

    var gpxSummaryText: String? {
        guard let mergedGpx, !mergedGpx.points.isEmpty else { return nil }
        return GpxParser.summary(mergedGpx)
    }

    // MARK: - 初期化

    init() {
        let ud = UserDefaults.standard
        let tzModeRaw = ud.string(forKey: Keys.tzMode) ?? Defaults.tzMode.rawValue
        self.tzMode = TzMode(rawValue: tzModeRaw) ?? Defaults.tzMode
        self.tzOffsetHours = ud.object(forKey: Keys.tzOffset) as? Double ?? Defaults.tzOffset
        self.overwriteGps = ud.object(forKey: Keys.overwriteGps) as? Bool ?? Defaults.overwriteGps
        self.maxTimeDiff = ud.object(forKey: Keys.maxTimeDiff) as? TimeInterval ?? Defaults.maxTimeDiff
        self.stationaryGapFill = ud.object(forKey: Keys.gapFill) as? Bool ?? Defaults.gapFill
        self.stationaryGapMaxDist = ud.object(forKey: Keys.gapDist) as? Double ?? Defaults.gapDist

        let folderPath = ud.string(forKey: Keys.photoFolder) ?? Defaults.photoFolder
        self.photoFolder = URL(fileURLWithPath: folderPath)
    }

    /// タブ初回表示時に呼ぶ。保存済みフォルダを自動読み込みする。
    func onFirstAppear() {
        guard !didAutoLoadFolder else { return }
        didAutoLoadFolder = true
        guard let photoFolder else { return }
        Task { await loadPhotoFolder(photoFolder) }
    }

    private var options: MatchOptions {
        MatchOptions(
            maxTimeDiff: maxTimeDiff,
            overwriteGps: overwriteGps,
            tzMode: tzMode,
            tzOffsetHours: tzOffsetHours,
            stationaryGapFill: stationaryGapFill,
            stationaryGapMaxDist: stationaryGapMaxDist
        )
    }

    // MARK: - GPX 操作

    /// .gpx を追加する。重複パスは無視。パース失敗・空ファイルも無視。
    /// パース（XML ストリーミング、GeoShutter 自動読み込みは数十ファイルに及ぶことがある）は
    /// メインスレッドをブロックしないようバックグラウンドで実行する。
    ///
    /// `XMLParser` の同期パースは async な一時停止点を持たない CPU 拘束処理のため、
    /// `TaskGroup`/`Task.detached` に直接乗せると Swift Concurrency の協調スレッドプール
    /// （コア数で固定サイズ）を専有し、無関係な MainActor の処理まで数秒〜十数秒単位で
    /// 遅延することを実測で確認した（同時実行数をコア数に制限しても軽減はするが解消しない）。
    /// そのため各ファイルのパースは `DispatchQueue.global()`（伸縮可能なスレッドプール）に
    /// 逃がし、`withCheckedContinuation` で async に橋渡しする。
    func addGpxFiles(_ urls: [URL]) {
        let newUrls = urls.filter { url in
            url.pathExtension.lowercased() == "gpx" && !loadedGpxFiles.contains(where: { $0.url == url })
        }
        guard !newUrls.isEmpty else { return }
        Task { await parseAndAppendGpxFiles(newUrls) }
    }

    private func parseAndAppendGpxFiles(_ urls: [URL]) async {
        busy = true
        gpxLoadProgress = (0, urls.count)
        defer {
            busy = false
            gpxLoadProgress = nil
        }

        let parsed = await withTaskGroup(of: (URL, GpxData?).self) { group -> [URL: GpxData] in
            for url in urls {
                group.addTask { (url, await Self.parseGpxOffCooperativePool(url)) }
            }
            var byURL: [URL: GpxData] = [:]
            var done = 0
            for await (url, data) in group {
                if let data {
                    byURL[url] = data
                }
                done += 1
                gpxLoadProgress = (done, urls.count)
            }
            return byURL
        }
        guard !parsed.isEmpty else { return }

        // 追加順を維持するため urls の順で並べ直す（元実装踏襲）
        for url in urls {
            if let data = parsed[url] {
                loadedGpxFiles.append((url, data))
            }
        }
        await recomputeMergedGpxAndPreview()
    }

    /// `XMLParser` の同期パースを `DispatchQueue.global()`（伸縮可能なスレッドプール）上で実行し、
    /// Swift Concurrency の協調スレッドプールを占有しないようにする。QoS は `.utility`
    /// （進捗表示のあるバックグラウンド一括処理向け）にして、OS スケジューラがメインスレッドを
    /// 優先できるようにする。
    private nonisolated static func parseGpxOffCooperativePool(_ url: URL) async -> GpxData? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let data = try? GpxParser.parse(contentsOf: url)
                continuation.resume(returning: (data?.points.isEmpty == false) ? data : nil)
            }
        }
    }

    func removeGpxFile(_ url: URL) {
        loadedGpxFiles.removeAll { $0.url == url }
        Task { await recomputeMergedGpxAndPreview() }
    }

    func clearGpxFiles() {
        loadedGpxFiles.removeAll()
        mergedGpx = nil
        resetMatchResultsToPending()
    }

    /// GPX マージ（数十万〜百万点規模になりうる）とマッチングをバックグラウンドで実行する。
    private func recomputeMergedGpxAndPreview() async {
        let dataList = loadedGpxFiles.map(\.data)
        guard !dataList.isEmpty else {
            mergedGpx = nil
            resetMatchResultsToPending()
            return
        }

        busy = true
        defer { busy = false }

        let merged = await Task.detached(priority: .userInitiated) {
            GpxParser.merge(dataList)
        }.value
        mergedGpx = merged

        guard !photoItems.isEmpty else { return }
        await runPreviewAsync(gpx: merged)
    }

    private func resetMatchResultsToPending() {
        matchResults = photoItems.map { MatchResult.pending($0) }
    }

    // MARK: - GeoShutter 自動読み込み

    /// GeoShutter フォルダから写真の撮影期間に重なる GPX を自動検出して読み込む。
    func autoLoadGeoShutter() {
        guard !photoItems.isEmpty else { return }
        let utcTimes = photoItems.compactMap(\.datetime)
        let candidateMin: Date
        let candidateMax: Date
        if !utcTimes.isEmpty {
            candidateMin = utcTimes.min()!
            candidateMax = utcTimes.max()!
        } else {
            // offsetStr なしのみの場合は raw 文字列を UTC 近似として使う（元実装と同じフォールバック）
            let rawDates = photoItems.compactMap { photo -> Date? in
                guard !photo.datetimeRaw.isEmpty else { return nil }
                return ExifReader.parseExifDate(photo.datetimeRaw, offsetStr: "+00:00")
            }
            guard !rawDates.isEmpty else { return }
            candidateMin = rawDates.min()!
            candidateMax = rawDates.max()!
        }

        let urls = GeoShutterLocator.candidates(
            photoMinUTC: candidateMin,
            photoMaxUTC: candidateMax,
            in: GeoShutterLocator.defaultFolder
        )
        guard !urls.isEmpty else { return }
        addGpxFiles(urls)
    }

    // MARK: - 写真フォルダ読み込み

    func chooseAndLoadPhotoFolder(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: Keys.photoFolder)
        photoFolder = url
        Task { await loadPhotoFolder(url) }
    }

    func loadPhotoFolder(_ folder: URL) async {
        busy = true
        defer { busy = false }

        let urls = ExifReader.listJpegs(in: folder)
        guard !urls.isEmpty else {
            photoItems = []
            matchResults = []
            loadProgress = nil
            return
        }

        loadProgress = (0, urls.count)
        let items = await ExifReader.readPhotos(at: urls) { [weak self] done, total in
            Task { @MainActor in
                self?.loadProgress = (done, total)
            }
        }
        loadProgress = nil

        photoItems = items
        resetMatchResultsToPending()

        if loadedGpxFiles.isEmpty {
            autoLoadGeoShutter()
        } else if mergedGpx != nil {
            runPreview()
        }
    }

    // MARK: - プレビュー（マッチング）

    func runPreview() {
        guard let mergedGpx, !photoItems.isEmpty else { return }
        Task { await runPreviewAsync(gpx: mergedGpx) }
    }

    /// マッチング本体（写真数 × GPX 点数）をバックグラウンドで実行する。
    private func runPreviewAsync(gpx: GpxData) async {
        let photos = photoItems
        let opts = options
        let results = await Task.detached(priority: .userInitiated) {
            Matcher.matchAll(gpxPoints: gpx.points, photos: photos, options: opts)
        }.value
        matchResults = results
    }

    // MARK: - 付与

    /// GPS/日時タグの書き込み。`GpsWriter.write` は exiftool サブプロセスを起動して
    /// `waitUntilExit()` するため同期ブロッキング呼び出しであり、GPX パースと同じ理由で
    /// `@MainActor` 上で直接呼ぶとメインスレッドが写真枚数 × exiftool 起動コストぶん
    /// フリーズする（実測で確認済み）。`DispatchQueue.global(qos: .utility)` へ逃がし、
    /// コア数を上限に並列実行する（書き込み先はファイルごとに異なるため競合しない）。
    func runApply() async {
        let targets = matchResults.enumerated().filter { $0.element.status == .ok }
        guard !targets.isEmpty else { return }

        busy = true
        applySummary = nil
        var success = 0
        var failed = 0
        let total = targets.count
        applyProgress = (0, total, 0, 0)

        let resolver: TimeZoneResolver?
        if timeZoneResolver == nil {
            resolver = try? TimeZoneResolver()
            timeZoneResolver = resolver
        } else {
            resolver = timeZoneResolver
        }

        var items: [(index: Int, request: GpsWriteRequest)] = []
        for (index, result) in targets {
            guard let match = result.match, let utcTime = result.utcTime else { continue }

            let localRewrite: LocalTimeRewrite?
            if !result.photo.datetimeRaw.isEmpty {
                localRewrite = resolver?.resolve(lat: match.point.lat, lon: match.point.lon, utcTime: utcTime)
            } else {
                localRewrite = nil
            }

            let request = GpsWriteRequest(
                url: result.photo.url,
                lat: match.point.lat,
                lon: match.point.lon,
                ele: match.point.ele,
                localRewrite: localRewrite
            )
            items.append((index, request))
        }

        // matchResults への書き込みを1件ごとに @Published へ反映すると、並列化により
        // 同一フレーム内で複数回発火して SwiftUI から
        // "onChange(of: Array<MatchResult>) action tried to update multiple times per frame"
        // という警告が出る（実測で確認済み）。ローカルコピーへ溜めてから間引いて反映する。
        let maxConcurrent = max(1, ProcessInfo.processInfo.activeProcessorCount)
        var localResults = matchResults
        let flushBatchSize = 20
        await withTaskGroup(of: (Int, Bool).self) { group in
            var iterator = items.makeIterator()
            func addNext() {
                guard let item = iterator.next() else { return }
                group.addTask { (item.index, await Self.writeGpsOffCooperativePool(item.request)) }
            }
            for _ in 0..<maxConcurrent { addNext() }

            var sinceFlush = 0
            while let (index, ok) = await group.next() {
                if ok {
                    localResults[index].status = .done
                    localResults[index].statusLabel = "✓ 書込済"
                    success += 1
                } else {
                    localResults[index].status = .error
                    localResults[index].statusLabel = "⚠ 書込失敗"
                    failed += 1
                }
                applyProgress = (success + failed, total, success, failed)
                sinceFlush += 1
                if sinceFlush >= flushBatchSize {
                    matchResults = localResults
                    sinceFlush = 0
                }
                addNext()
            }
        }
        matchResults = localResults

        applySummary = "完了：成功 \(success) 件 / 失敗 \(failed) 件"
        applyProgress = nil
        busy = false
    }

    private nonisolated static func writeGpsOffCooperativePool(_ request: GpsWriteRequest) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    try GpsWriter.write(request)
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }
}

// MARK: - 表示フォーマット共通ヘルパー

/// テーブル・プレビューパネル双方で使う日時表示・状態色などの整形ロジック。
/// 元 app.ts の `gpxTimeToLocal` / `statusClass` 相当。
enum GeoTaggerFormat {
    /// EXIF 原文 "2026:04:13 04:52:50" を "2026-04-13 04:52" + オフセットに整形。
    static func datetimeRaw(_ raw: String, offsetStr: String?) -> String {
        guard !raw.isEmpty else { return "—" }
        let prefix = String(raw.prefix(16))
        let parts = prefix.split(separator: " ", maxSplits: 1).map(String.init)
        guard let datePart = parts.first else { return "—" }
        let dateComponents = datePart.split(separator: ":")
        guard dateComponents.count == 3 else { return "—" }
        let dateStr = dateComponents.joined(separator: "-")
        let timeStr = parts.count > 1 ? parts[1] : ""
        let base = timeStr.isEmpty ? dateStr : "\(dateStr) \(timeStr)"
        if let offsetStr { return "\(base) \(offsetStr)" }
        return base
    }

    /// GPX マッチ時刻（UTC）を写真の offsetStr による現地表示へ変換。offsetStr が無ければ UTC 表記。
    static func gpxTimeToLocal(_ gpxTime: Date?, offsetStr: String?) -> String {
        guard let gpxTime else { return "—" }
        let utcFormatter = DateFormatter()
        utcFormatter.locale = Locale(identifier: "en_US_POSIX")
        utcFormatter.timeZone = TimeZone(identifier: "UTC")
        utcFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        guard let offsetStr, let seconds = offsetSeconds(from: offsetStr) else {
            return utcFormatter.string(from: gpxTime) + " UTC"
        }
        let local = gpxTime.addingTimeInterval(TimeInterval(seconds))
        return utcFormatter.string(from: local) + " \(offsetStr)"
    }

    /// "+09:00" / "-08:00" → 秒数
    private static func offsetSeconds(from offsetStr: String) -> Int? {
        let pattern = #"^([+-])(\d{2}):(\d{2})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(offsetStr.startIndex..., in: offsetStr)
        guard let match = regex.firstMatch(in: offsetStr, range: range) else { return nil }
        func group(_ idx: Int) -> String {
            let r = match.range(at: idx)
            return (offsetStr as NSString).substring(with: r)
        }
        let sign = group(1) == "+" ? 1 : -1
        let hh = Int(group(2)) ?? 0
        let mm = Int(group(3)) ?? 0
        return sign * (hh * 60 + mm) * 60
    }

    static func coord(lat: Double, lon: Double, digits: Int = 4) -> String {
        String(format: "%.\(digits)f, %.\(digits)f", lat, lon)
    }

    static func statusColor(_ status: MatchStatus) -> Color {
        switch status {
        case .ok, .done: return Palette.success
        case .warning: return Palette.warning
        case .error: return Palette.danger
        case .skip: return Palette.neutral
        case .pending: return Palette.text2
        }
    }
}
