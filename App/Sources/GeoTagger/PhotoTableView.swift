import SwiftUI
import GeoTaggerCore

/// 写真テーブル: ファイル名 / 撮影時刻 / GPX時刻 / 座標 / 時間差 / 状態 の 6 列。
/// SwiftUI `Table` + `KeyPathComparator` で全列ソート可能（既定: GPX 時刻＝UTC 昇順）。
struct PhotoTableView: View {
    let results: [MatchResult]
    @Binding var selection: URL?

    @State private var sortOrder: [KeyPathComparator<MatchResult>] = [
        .init(\.utcTimeSortKey, order: .forward)
    ]

    private var sortedResults: [MatchResult] {
        results.sorted(using: sortOrder)
    }

    var body: some View {
        Table(sortedResults, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("ファイル名", value: \.photo.url.lastPathComponent) { r in
                Text(r.photo.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(r.photo.url.path)
            }
            .width(min: 120, ideal: 180)

            TableColumn("撮影時刻", value: \.photo.datetimeRaw) { r in
                Text(GeoTaggerFormat.datetimeRaw(r.photo.datetimeRaw, offsetStr: r.photo.offsetStr))
            }
            .width(min: 120, ideal: 170)

            TableColumn("GPX時刻", value: \.utcTimeSortKey) { r in
                Text(GeoTaggerFormat.gpxTimeToLocal(r.match?.point.time, offsetStr: r.photo.offsetStr))
            }
            .width(min: 120, ideal: 170)

            TableColumn("座標", value: \.coordSortKey) { r in
                if let match = r.match {
                    Text(GeoTaggerFormat.coord(lat: match.point.lat, lon: match.point.lon))
                } else {
                    Text("—")
                }
            }
            .width(min: 100, ideal: 150)

            TableColumn("時間差", value: \.diffSortKey) { r in
                if let match = r.match {
                    Text(Matcher.fmtDiff(match.diffSec))
                } else {
                    Text("—")
                }
            }
            .width(min: 60, ideal: 80)

            TableColumn("状態", value: \.statusLabel) { r in
                Text(r.statusLabel)
                    .foregroundStyle(GeoTaggerFormat.statusColor(r.status))
            }
            .width(min: 90, ideal: 110)
        }
    }
}

private extension MatchResult {
    /// utcTime が nil の行は末尾に来るよう -infinity 相当を使う（元 app.ts の sortKey と同じ扱い）。
    var utcTimeSortKey: Double {
        utcTime?.timeIntervalSinceReferenceDate ?? -.infinity
    }
    var coordSortKey: Double {
        match?.point.lat ?? -.infinity
    }
    var diffSortKey: Double {
        match?.diffSec ?? .infinity
    }
}
