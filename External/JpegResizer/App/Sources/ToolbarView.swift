import SwiftUI
import JpegResizerCore

/// 上部ツールバー：品質・サイズを**フローレイアウト**で並べる。
/// ウィンドウ幅が広ければ 1 段に収め、狭ければ次の段へ自動的に折り返す。
/// 実行ボタン（変換 / クリア）は画面下部の FooterBarView へ分離。
struct ToolbarView: View {
    @EnvironmentObject var model: AppViewModel

    var body: some View {
        FlowLayout(hSpacing: 16, vSpacing: 8) {
            qualitySection
            sizeSection
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - セクション

    /// 品質スライダー。
    private var qualitySection: some View {
        HStack(spacing: 8) {
            Text("品質")
            Slider(value: $model.quality, in: 0.0...1.0)
                .frame(width: 140)
                .disabled(!model.canEditSettings)
            Text(String(format: "%.2f", model.quality))
                .monospacedDigit()
                .frame(width: 38, alignment: .leading)
        }
        .fixedSize()
    }

    // MARK: - サイズ（書き出し時のリサイズ。縮小のみ・アスペクト比維持）

    private var sizeSection: some View {
        HStack(spacing: 8) {
            Text("サイズ")
            Picker("", selection: $model.resizeKind) {
                Text("元のサイズ").tag(ResizeKind.original)
                Text("総画素数").tag(ResizeKind.megapixels)
                Text("横幅").tag(ResizeKind.width)
                Text("縦幅").tag(ResizeKind.height)
            }
            .labelsHidden()
            .frame(width: 100)
            .disabled(!model.canEditSettings)
            .help("書き出し時に縮小します（拡大はしません・アスペクト比は維持）。総画素数は 8=約800万画素の目安。")

            switch model.resizeKind {
            case .original:
                EmptyView()
            case .megapixels:
                mpixField()
            case .width:
                pixelField(value: $model.resizeWidth, presets: [1280, 1920, 2560, 3840, 4096])
            case .height:
                pixelField(value: $model.resizeHeight, presets: [720, 1080, 1440, 2160])
            }
        }
        .fixedSize()
    }

    /// 総画素数（Mpix, Double）用の数値フィールド＋プリセット。自由入力とプリセットを両立する。
    @ViewBuilder
    private func mpixField() -> some View {
        HStack(spacing: 4) {
            TextField("", value: $model.resizeMegapixels, format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 48)
                .disabled(!model.canEditSettings)
            presetMenu(presets: [2.0, 4.0, 8.0, 12.0, 16.0, 24.0],
                       label: { "\(Int($0)) Mpix" }) { model.resizeMegapixels = $0 }
            Text("Mpix").foregroundStyle(.secondary)
        }
    }

    /// 幅/高さ（px, Int）用の数値フィールド＋プリセット。
    @ViewBuilder
    private func pixelField(value: Binding<Int>, presets: [Int]) -> some View {
        HStack(spacing: 4) {
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
                .disabled(!model.canEditSettings)
            presetMenu(presets: presets, label: { "\($0) px" }) { value.wrappedValue = $0 }
            Text("px").foregroundStyle(.secondary)
        }
    }

    /// プリセット値を並べる小さなドロップダウン（⌄）。選ぶと数値フィールドへ反映する。
    @ViewBuilder
    private func presetMenu<V>(presets: [V], label: @escaping (V) -> String,
                               apply: @escaping (V) -> Void) -> some View {
        Menu {
            ForEach(Array(presets.enumerated()), id: \.offset) { _, v in
                Button(label(v)) { apply(v) }
            }
        } label: {
            Image(systemName: "chevron.down")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)   // 自前の chevron を出すので組み込みインジケータは隠す（二重表示防止）
        .frame(width: 24)
        .disabled(!model.canEditSettings)
        .help("よく使うサイズを選ぶ")
    }
}

/// 左→右に子ビューを並べ、行に入り切らない子を次の行へ折り返す簡易フローレイアウト。
/// 各子はそれぞれの固有サイズ（`.fixedSize()` 済みの各セクション）で配置する。
/// ウィンドウ幅に応じてツールバーの段数が 1〜N に伸縮する。
struct FlowLayout: Layout {
    var hSpacing: CGFloat = 16   // 同一行内の水平間隔
    var vSpacing: CGFloat = 8    // 折り返した行間の垂直間隔

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0, rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0, totalHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + hSpacing + size.width > maxWidth {
                totalHeight += rowHeight + vSpacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? hSpacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + vSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + hSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
