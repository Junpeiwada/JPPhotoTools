import SwiftUI
import UniformTypeIdentifiers
import GeoTaggerCore

/// 「ジオタグ」タブのルート。HSplitView（左サイドバー | 右ペイン）、
/// 右ペインは VSplitView（地図 / プレビュー / 写真テーブル）。
/// 元 GeoTagger（Electron）の 1 ウィンドウ構成をタブ内の分割ペインで再現する。
struct GeoTaggerTab: View {
    @StateObject private var viewModel = GeoTaggerViewModel()

    // ペイン寸法（元 app.ts の localStorage 'geo-sidebar-w' / 'geo-bottom-h' 相当）。
    @AppStorage("geoTaggerSidebarWidth") private var sidebarWidth: Double = 280
    @AppStorage("geoTaggerMapHeight") private var mapHeight: Double = 380
    @AppStorage("geoTaggerPreviewHeight") private var previewHeight: Double = 190

    @State private var selectedResult: MatchResult?
    @State private var isDropTargeted = false

    var body: some View {
        HSplitView {
            GpxSidebarView(viewModel: viewModel)
                .frame(minWidth: 240, idealWidth: sidebarWidth, maxWidth: 420)

            VSplitView {
                GeoMapView(
                    mergedGpx: viewModel.mergedGpx,
                    matchResults: viewModel.matchResults,
                    selection: $viewModel.selection
                )
                .frame(minHeight: 200, idealHeight: mapHeight)

                PhotoPreviewPane(result: selectedResult)
                    .frame(minHeight: 130, idealHeight: previewHeight, maxHeight: 320)

                PhotoTableView(results: viewModel.matchResults, selection: $viewModel.selection)
                    .frame(minHeight: 160)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if viewModel.busy, let progress = viewModel.loadProgress {
                loadingOverlay(progress)
            }
        }
        .onChange(of: viewModel.selection) { _, newValue in
            selectedResult = viewModel.matchResults.first { $0.photo.url == newValue }
        }
        .onChange(of: viewModel.matchResults) { _, newResults in
            guard let selection = viewModel.selection else { selectedResult = nil; return }
            selectedResult = newResults.first { $0.photo.url == selection }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let gpxUrls = urls.filter { $0.pathExtension.lowercased() == "gpx" }
            guard !gpxUrls.isEmpty else { return false }
            viewModel.addGpxFiles(gpxUrls)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .task {
            viewModel.onFirstAppear()
        }
    }

    private func loadingOverlay(_ progress: (done: Int, total: Int)) -> some View {
        VStack(spacing: 8) {
            Text("写真を読み込み中…")
            ProgressView(value: Double(progress.done), total: Double(progress.total))
                .frame(width: 240)
            Text("\(progress.done) / \(progress.total)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    GeoTaggerTab()
}
