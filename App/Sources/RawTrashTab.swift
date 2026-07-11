import SwiftUI
import UniformTypeIdentifiers
import RawTrashCore

/// 「取り込み・整理」タブ。フォルダを受け取り、RAW/JPG ペアを仕分けて
/// 孤立 RAW を Del/ へ退避する（`RawTrashCore.RawTrash.sort`）。
///
/// 変換系タブ（GainForge / JpegResizer）と違い、ファイル単位のプレビューやバッチ並列は無く、
/// 「フォルダを選ぶ → 仕分ける → 件数を見る」だけの単純なフローなので専用の軽量 UI にする。
struct RawTrashTab: View {
    @State private var folder: URL?
    @State private var isSorting = false
    @State private var result: RawTrash.SortResult?
    @State private var errorMessage: String?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 20) {
            Text("取り込み・整理")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            dropArea

            if let folder {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text(folder.path)
                        .lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("フォルダを選択…") { chooseFolder() }
                    .disabled(isSorting)
                Button(isSorting ? "仕分け中…" : "仕分けを実行") { runSort() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(folder == nil || isSorting)
            }

            if let result {
                resultView(result)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.danger)
                    .font(.callout)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var dropArea: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
            .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
            .frame(height: 120)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("整理したいフォルダをここにドロップ")
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                loadDroppedFolder(providers)
            }
    }

    private func resultView(_ r: RawTrash.SortResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("仕分け完了（合計 \(r.total) 件）").font(.headline)
            HStack(spacing: 16) {
                countChip("Del", r.deleted, Palette.danger)
                countChip("RAW", r.raw, Palette.info)
                countChip("JPG", r.jpg, Palette.success)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.elevated, in: RoundedRectangle(cornerRadius: 8))
    }

    private func countChip(_ label: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(label): \(count)").monospacedDigit()
        }
    }

    // MARK: - アクション

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            setFolder(url)
        }
    }

    /// ドロップされた最初のフォルダ URL を受け取る（ファイルは無視）。
    private func loadDroppedFolder(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue
            else { return }
            Task { @MainActor in setFolder(url) }
        }
        return true
    }

    private func setFolder(_ url: URL) {
        folder = url
        result = nil
        errorMessage = nil
    }

    private func runSort() {
        guard let folder else { return }
        isSorting = true
        result = nil
        errorMessage = nil
        Task {
            let outcome: Result<RawTrash.SortResult, Error> = await Task.detached {
                do { return .success(try RawTrash.sort(folderPath: folder)) }
                catch { return .failure(error) }
            }.value
            isSorting = false
            switch outcome {
            case .success(let r):   result = r
            case .failure(let e):   errorMessage = e.localizedDescription
            }
        }
    }
}

#Preview {
    RawTrashTab()
}
