import SwiftUI
import GainForgeApp

/// 統合アプリのエントリポイント。
///
/// 撮影後ワークフローを時系列（取り込み・整理 → HDR 変換 → リサイズ書き出し）に並べた
/// TabView を単一ウィンドウで表示する。各タブの中身は機能ごとの App 層モジュール
/// （GainForgeApp / JpegResizerApp）と統合アプリ内の RawTrashTab が担う。
///
/// GainForge の比較ビューワは元アプリと同じく「別ウィンドウ」で開く。そのための共有状態
/// `ViewerModel` はここ（ルート）で 1 つだけ保持し、GainForge タブとビューワ Window シーンの
/// 双方へ同一インスタンスを environmentObject 注入して共有する。
@main
struct JPPhotoToolsApp: App {
    // GainForge の比較ビューワの共有状態。タブとビューワ Window で同一インスタンスを共有する。
    @StateObject private var gainForgeViewer = ViewerModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(gainForgeViewer)
                .frame(minWidth: 560, minHeight: 480)
        }
        .windowResizability(.contentMinSize)

        // 比較ビューワ（別ウィンドウ・単一インスタンス）。GainForge タブの行ダブルクリックで
        // モジュール内から openWindow(id:) が呼ばれ、同じ gainForgeViewer に内容がセットされる。
        Window("比較ビューワ", id: GainForgeTab.viewerWindowID) {
            ViewerView()
                .environmentObject(gainForgeViewer)
        }
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}
