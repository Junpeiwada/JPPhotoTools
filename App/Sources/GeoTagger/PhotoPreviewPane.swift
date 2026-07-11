import SwiftUI
import GeoTaggerCore

/// 選択写真のプレビューパネル。サムネイル + メタ情報。元 index.html の `#preview-panel` 相当。
struct PhotoPreviewPane: View {
    let result: MatchResult?

    @State private var thumbnail: NSImage?
    @State private var loadedURL: URL?

    /// 未選択時も選択時と同一の骨格（サムネ枠＋グリッド）を描画する。
    /// 別ビュー階層に分岐させると行クリック時にレイアウトが一気に切り替わって見えるため、
    /// 値だけをプレースホルダ（「—」）に差し替えて骨格は常に同じにする。
    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            Group {
                if let thumbnail {
                    HDRImageView(image: thumbnail)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .overlay {
                            if result == nil {
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                }
            }
            .frame(minWidth: 140, idealWidth: 220, maxWidth: 280, minHeight: 105, idealHeight: 165, maxHeight: 210)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 12) {
                Text(result?.photo.url.lastPathComponent ?? "写真リストから行を選択")
                    .font(.headline)
                    .foregroundStyle(result == nil ? .secondary : .primary)

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 28, verticalSpacing: 8) {
                    GridRow {
                        metaRow("撮影時刻", result.map { GeoTaggerFormat.datetimeRaw($0.photo.datetimeRaw, offsetStr: $0.photo.offsetStr) } ?? "—")
                        metaRow("GPX時刻", GeoTaggerFormat.gpxTimeToLocal(result?.match?.point.time, offsetStr: result?.photo.offsetStr))
                    }
                    GridRow {
                        metaRow("座標", result?.match.map { GeoTaggerFormat.coord(lat: $0.point.lat, lon: $0.point.lon, digits: 5) } ?? "—")
                        metaRow("高度", result?.match?.point.ele.map { String(format: "%.1f m", $0) } ?? "—")
                    }
                    GridRow {
                        metaRow("時間差", result?.match.map { Matcher.fmtDiff($0.diffSec) } ?? "—")
                        HStack(spacing: 6) {
                            Text("状態").font(.caption).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
                            Text(result?.statusLabel ?? "—")
                                .foregroundStyle(result.map { GeoTaggerFormat.statusColor($0.status) } ?? .secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .task(id: result?.photo.url) {
            loadThumbnail(for: result)
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
            Text(value).font(.callout)
        }
    }

    /// NSImage で直接・非同期読み込み（元実装の Base64 経由読み込みは不要）。
    // （HDR 描画は末尾の HDRImageView が担う）
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

/// `NSImageView` を EDR（HDR）描画有効でラップする。
/// SwiftUI の `Image(nsImage:)` は EDR 描画パスを持たず SDR にクランプされるため、
/// HDR 画像（ゲインマップ付き HEIC/JPEG など）を正しく表示するには AppKit のビューが必要。
private struct HDRImageView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageAlignment = .alignCenter
        // 拡張ダイナミックレンジで描画（対応ディスプレイでハイライトが伸びる）
        view.preferredImageDynamicRange = .high
        // 枠に追従して縮小できるよう圧縮抵抗を下げる
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.image = image
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = image
        nsView.preferredImageDynamicRange = .high
    }
}
