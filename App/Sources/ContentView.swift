import SwiftUI
import GainForgeApp
import JpegResizerApp

/// 統合アプリのタブ器。撮影後の処理を時系列順に4タブで並べる。
///
/// 各タブの中身:
///   - 取り込み・整理: RawTrashTab（統合アプリ内・RawTrashCore を直接使用）
///   - HDR 変換: GainForgeTab（GainForgeApp モジュール）
///   - リサイズ書き出し: JpegResizerTab（JpegResizerApp モジュール）
///   - ジオタグ: GeoTaggerTab（統合アプリ内・GeoTaggerCore を直接使用）
///
/// GainForge タブは比較ビューワ（別ウィンドウ）の共有状態 `ViewerModel` をルートから
/// environmentObject で受け取り、そのままタブへ引き渡す。
struct ContentView: View {
    /// ルート（JPPhotoToolsApp）が保持する比較ビューワの共有状態。GainForge タブへ渡す。
    @EnvironmentObject private var gainForgeViewer: ViewerModel

    enum Tab: Hashable {
        case organize, hdr, resize, geoTagger

        /// タブの署名色（機能別マルチ差し色）。選択中タブの色を tint として流す。
        var accent: Color {
            switch self {
            case .organize:  return Palette.tabOrganize
            case .hdr:       return Palette.tabHDR
            case .resize:    return Palette.tabResize
            case .geoTagger: return Palette.tabGeo
            }
        }
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

            GeoTaggerTab()
                .tabItem { Label("ジオタグ", systemImage: "mappin.and.ellipse") }
                .tag(Tab.geoTagger)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 差し色: 選択中タブの署名色を environment の tint として流す。別モジュールの
        // タブ配下のコントロール（ボタン・選択ハイライト等）にもこの色が伝播する。
        .tint(selection.accent)
        // 黒基調カラースキーム: システム設定によらず常にダーク表示で固定する。
        .preferredColorScheme(.dark)
    }
}
