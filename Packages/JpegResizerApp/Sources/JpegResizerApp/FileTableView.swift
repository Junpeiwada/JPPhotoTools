import SwiftUI
import AppKit

/// 中央のファイル一覧テーブル（ドロップ受付兼用）。空のときは Empty state。
struct FileTableView: View {
    @EnvironmentObject var model: AppViewModel
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            if model.items.isEmpty {
                EmptyStateView()
            } else {
                table
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(dropHighlight)
        // 一覧テーブル領域全体で D&D を受け付ける。
        .dropDestination(for: URL.self) { urls, _ in
            model.addDropped(urls)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private var table: some View {
        Table(model.items, selection: $model.selection) {
            TableColumn("") { item in
                cell { thumbnail(item) }
            }
            .width(44)

            TableColumn("ファイル名") { item in
                cell {
                    Text(item.displayName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(item.inputURL.path)
                }
            }
            .width(min: 140, ideal: 220)

            TableColumn("寸法") { item in
                cell {
                    Text(SizeFormat.dimensionBeforeAfter(
                        original: item.pixelSize,
                        output: outputDimension(item)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 150, ideal: 190)

            TableColumn("状態") { item in
                cell {
                    HStack(spacing: 6) {
                        item.status.chip
                        if item.status == .error, let msg = item.errorMessage {
                            Image(systemName: "info.circle").foregroundStyle(.secondary).help(msg)
                        }
                    }
                }
            }
            .width(100)

            TableColumn("サイズ") { item in
                cell {
                    Text(SizeFormat.beforeAfter(input: item.inputBytes, output: item.outputBytes, status: item.status))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 110, ideal: 140)
        }
        .contextMenu(forSelectionType: FileItem.ID.self) { ids in
            rowMenu(ids)
        }
        .onDeleteCommand { if !model.selection.isEmpty { model.remove(ids: model.selection) } }
        // Esc で選択を解除し、変換対象を「全件」に戻せるようにする。
        .onExitCommand { model.selection.removeAll() }
    }

    /// 表示する出力寸法。完了行は実際の出力寸法、未変換行は現在のリサイズ設定での予測寸法。
    private func outputDimension(_ item: FileItem) -> CGSize? {
        if let out = item.outputPixelSize { return out }
        guard let original = item.pixelSize else { return nil }
        return model.plannedOutputSize(for: original)
    }

    /// セル内容を左寄せ・全幅で配置する。
    private func cell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func thumbnail(_ item: FileItem) -> some View {
        if let img = item.thumbnail {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 32, height: 32)
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
    }

    @ViewBuilder
    private func rowMenu(_ ids: Set<FileItem.ID>) -> some View {
        Button("一覧から削除") { model.remove(ids: ids) }
            .disabled(model.isConverting)
        Button("Finder で表示") {
            let urls = model.items.filter { ids.contains($0.id) }.map { $0.inputURL }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
        // 完了行は出力 JPEG を Finder で表示。
        let outputs = model.items.filter { ids.contains($0.id) }.compactMap { $0.outputURL }
        if !outputs.isEmpty {
            Button("出力 JPEG を Finder で表示") {
                NSWorkspace.shared.activateFileViewerSelecting(outputs)
            }
        }
    }

    @ViewBuilder
    private var dropHighlight: some View {
        if isTargeted {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.accentColor, lineWidth: 2)
                .padding(2)
        }
    }
}

/// 一覧が空のときのプレースホルダ。
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("ここに画像 / フォルダをドラッグ&ドロップ")
                .font(.title3)
            Text("フォルダ内の JPEG / PNG / HEIC / TIFF を再帰的に読み込みます")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
