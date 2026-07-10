import SwiftUI
import GainForgeApp
import JpegResizerApp

/// 統合アプリのタブ器。撮影後の処理を時系列順に3タブで並べる。
///
/// 各タブの中身:
///   - 取り込み・整理: RawTrashTab（統合アプリ内・RawTrashCore を直接使用）
///   - HDR 変換: GainForgeTab（GainForgeApp モジュール）
///   - リサイズ書き出し: JpegResizerTab（JpegResizerApp モジュール）
///
/// GainForge タブは比較ビューワ（別ウィンドウ）の共有状態 `ViewerModel` をルートから
/// environmentObject で受け取り、そのままタブへ引き渡す。
struct ContentView: View {
    /// ルート（JPPhotoToolsApp）が保持する比較ビューワの共有状態。GainForge タブへ渡す。
    @EnvironmentObject private var gainForgeViewer: ViewerModel

    enum Tab: Hashable {
        case organize, hdr, resize
    }
    @State private var selection: Tab = .organize

    var body: some View {
        TabView(selection: $selection) {
            RawTrashTab()
                .tabItem { Label("取り込み・整理", systemImage: "tray.and.arrow.down") }
                .tag(Tab.organize)

            GainForgeTab()
                .environmentObject(gainForgeViewer)
                .tabItem { Label("HDR 変換", systemImage: "camera.filters") }
                .tag(Tab.hdr)

            JpegResizerTab()
                .tabItem { Label("リサイズ書き出し", systemImage: "arrow.down.right.and.arrow.up.left") }
                .tag(Tab.resize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
