import SwiftUI
import GeoTaggerCore

/// 左サイドバー: GPX リスト・写真フォルダ・TZ 設定・しきい値設定・付与ボタン。
/// 元 index.html の `#sidebar` を SwiftUI Form 風に再現する。
struct GpxSidebarView: View {
    @ObservedObject var viewModel: GeoTaggerViewModel
    @State private var showApplyConfirm = false

    private let tzOffsets: [Int] = Array(-12...14)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                gpxSection
                Divider()
                photoFolderSection
                Divider()
                tzSection
                Divider()
                optionsSection
                Divider()
                applySection
            }
            .padding(12)
        }
        .frame(minWidth: 260, idealWidth: 280)
    }

    // MARK: - GPX

    private var gpxSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GPX ファイル").font(.headline)

            Button("GeoShutter から読み込む") { viewModel.autoLoadGeoShutter() }
                .disabled(viewModel.busy)
                .frame(maxWidth: .infinity)

            HStack {
                Button("選択…") { chooseGpxFiles() }
                    .disabled(viewModel.busy)
                Button("クリア") { viewModel.clearGpxFiles() }
                    .disabled(viewModel.busy || viewModel.loadedGpxFiles.isEmpty)
            }

            if viewModel.loadedGpxFiles.isEmpty {
                Text("ここに GPX をドロップ（複数可）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.loadedGpxFiles, id: \.url) { entry in
                        HStack {
                            Text(entry.url.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(entry.url.path)
                            Spacer()
                            Button {
                                viewModel.removeGpxFile(entry.url)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .disabled(viewModel.busy)
                        }
                    }
                }
            }

            if let summary = viewModel.gpxSummaryText {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chooseGpxFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.init(filenameExtension: "gpx")].compactMap { $0 }
        if panel.runModal() == .OK {
            viewModel.addGpxFiles(panel.urls)
        }
    }

    // MARK: - 写真フォルダ

    private var photoFolderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("写真フォルダ").font(.headline)
            HStack {
                Text(viewModel.photoFolder?.path ?? "—")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("選択…") { choosePhotoFolder() }
                    .disabled(viewModel.busy)
            }

            if let loadProgress = viewModel.loadProgress {
                ProgressView(value: Double(loadProgress.done), total: Double(loadProgress.total))
                Text("\(loadProgress.done) / \(loadProgress.total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !viewModel.photoItems.isEmpty {
                Text("\(viewModel.photoItems.count) 枚  ✓ \(viewModel.okCount)件  ⚠ \(viewModel.warningCount)件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.noOffsetCount > 0 {
                Text("⚠ OffsetTimeOriginal がないファイルが \(viewModel.noOffsetCount) 枚あります（手動 TZ を検討してください）。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func choosePhotoFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.chooseAndLoadPhotoFolder(url)
        }
    }

    // MARK: - タイムゾーン

    private var tzSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("タイムゾーン").font(.headline)

            Picker("", selection: $viewModel.tzMode) {
                Text("Exif 自動（推奨）").tag(TzMode.auto)
                Text("手動").tag(TzMode.manual)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Picker("オフセット", selection: $viewModel.tzOffsetHours) {
                ForEach(tzOffsets, id: \.self) { h in
                    Text("UTC\(h >= 0 ? "+" : "")\(h)").tag(Double(h))
                }
            }
            .disabled(viewModel.tzMode != .manual)
            .frame(maxWidth: 160)
        }
    }

    // MARK: - オプション

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("オプション").font(.headline)

            Toggle("既存の GPS タグを上書き", isOn: $viewModel.overwriteGps)

            HStack {
                Text("最大時間差")
                TextField("", value: $viewModel.maxTimeDiff, format: .number)
                    .frame(width: 70)
                Text("秒")
            }

            Toggle("静止ギャップ補完", isOn: $viewModel.stationaryGapFill)

            HStack {
                Text("補完距離閾値")
                TextField("", value: $viewModel.stationaryGapMaxDist, format: .number)
                    .frame(width: 70)
                    .disabled(!viewModel.stationaryGapFill)
                Text("m")
            }
            .opacity(viewModel.stationaryGapFill ? 1.0 : 0.4)
        }
    }

    // MARK: - 付与

    private var applySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("付与") { showApplyConfirm = true }
                .disabled(!viewModel.canApply)
                .frame(maxWidth: .infinity)
                .keyboardShortcut(.defaultAction)
                .confirmationDialog(
                    "✓ 完了 \(viewModel.okCount) 件に GPS タグを書き込みます。よろしいですか？",
                    isPresented: $showApplyConfirm,
                    titleVisibility: .visible
                ) {
                    Button("書き込む") { Task { await viewModel.runApply() } }
                    Button("キャンセル", role: .cancel) {}
                }

            if let progress = viewModel.applyProgress {
                ProgressView(value: Double(progress.done), total: Double(progress.total))
                Text("\(progress.done) / \(progress.total)（✓ \(progress.success)\(progress.failed > 0 ? "  ⚠ \(progress.failed)" : "")）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let summary = viewModel.applySummary {
                Text(summary)
                    .font(.caption)
            }
        }
    }
}
