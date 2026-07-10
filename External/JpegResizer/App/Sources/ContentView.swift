import SwiftUI

/// 単一ウィンドウ・画面遷移なし。ツールバー / 一覧テーブル / フッター / ステータスバーの 4 エリア。
struct ContentView: View {
    @EnvironmentObject var model: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView()
            Divider()
            FileTableView()
            Divider()
            // 実行ボタン（変換 / クリア）は画面下端・ステータスバーの直上に固定表示する。
            FooterBarView()
            Divider()
            StatusBarView()
        }
    }
}
