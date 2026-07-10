import SwiftUI

/// 角丸の小さなラベル（状態表示・メタ表示用）。
///
/// GainForge / JpegResizer で共通だった `Chip` 本体を共通化。機能固有の chip 拡張
/// （`GainMapState.chip` / `RowStatus.chip` など、機能固有の enum に生える computed property）は
/// 各機能モジュールに残す（RowStatus 等が機能ごとに異なるため）。この `Chip` を組み立て部品として使う。
public struct Chip: View {
    let text: String
    let systemImage: String?
    let color: Color
    var filled: Bool = false

    public init(_ text: String, systemImage: String? = nil, color: Color, filled: Bool = false) {
        self.text = text
        self.systemImage = systemImage
        self.color = color
        self.filled = filled
    }

    public var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(filled ? color.opacity(0.18) : Color.secondary.opacity(0.12))
        .foregroundStyle(filled ? color : .secondary)
        .clipShape(Capsule())
    }
}
