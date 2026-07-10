import SwiftUI

/// 左→右に子ビューを並べ、行に入り切らない子を次の行へ折り返す簡易フローレイアウト。
/// 各子はそれぞれの固有サイズ（`.fixedSize()` 済みの各セクション）で配置する。
/// ウィンドウ幅に応じてツールバーの段数が 1〜N に伸縮する。
///
/// GainForge / JpegResizer のツールバーで完全一致していたものを共通化。
public struct FlowLayout: Layout {
    var hSpacing: CGFloat = 16   // 同一行内の水平間隔
    var vSpacing: CGFloat = 8    // 折り返した行間の垂直間隔

    public init(hSpacing: CGFloat = 16, vSpacing: CGFloat = 8) {
        self.hSpacing = hSpacing
        self.vSpacing = vSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        // 前提: 有限幅が提案される文脈（VStack 直下など）で使う。提案幅が nil のときは
        // 単一行として高さを申告する（実配置で折り返すとクリップし得るので無限幅では使わない）。
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0, rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0, totalHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + hSpacing + size.width > maxWidth {
                // この子は入り切らない → 改行
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

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                // 行末を超える → 改行
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
