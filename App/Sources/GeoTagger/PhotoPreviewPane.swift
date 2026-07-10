import SwiftUI
import GeoTaggerCore

/// 選択写真のプレビューパネル。サムネイル + メタ情報。元 index.html の `#preview-panel` 相当。
struct PhotoPreviewPane: View {
    let result: MatchResult?

    @State private var thumbnail: NSImage?
    @State private var loadedURL: URL?

    var body: some View {
        Group {
            if let result {
                content(for: result)
            } else {
                Text("写真リストから行を選択")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: result?.photo.url) {
            loadThumbnail(for: result)
        }
    }

    private func content(for r: MatchResult) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary)
                }
            }
            .frame(width: 160, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 6) {
                Text(r.photo.url.lastPathComponent)
                    .font(.headline)

                metaRow("撮影時刻", GeoTaggerFormat.datetimeRaw(r.photo.datetimeRaw, offsetStr: r.photo.offsetStr))
                metaRow("GPX時刻", GeoTaggerFormat.gpxTimeToLocal(r.match?.point.time, offsetStr: r.photo.offsetStr))
                metaRow("座標", r.match.map { GeoTaggerFormat.coord(lat: $0.point.lat, lon: $0.point.lon, digits: 5) } ?? "—")
                metaRow("高度", r.match?.point.ele.map { String(format: "%.1f m", $0) } ?? "—")
                metaRow("時間差", r.match.map { Matcher.fmtDiff($0.diffSec) } ?? "—")
                HStack(spacing: 4) {
                    Text("状態").font(.caption).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
                    Text(r.statusLabel).foregroundStyle(GeoTaggerFormat.statusColor(r.status))
                }
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
            Text(value).font(.callout)
        }
    }

    /// NSImage で直接・非同期読み込み（元実装の Base64 経由読み込みは不要）。
    private func loadThumbnail(for result: MatchResult?) {
        guard let url = result?.photo.url else {
            thumbnail = nil
            loadedURL = nil
            return
        }
        guard url != loadedURL else { return }
        loadedURL = url
        thumbnail = nil
        Task.detached(priority: .userInitiated) {
            let image = NSImage(contentsOf: url)
            await MainActor.run {
                guard loadedURL == url else { return }
                thumbnail = image
            }
        }
    }
}
