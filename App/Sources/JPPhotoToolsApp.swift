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
    // アプリ内自動更新（Sparkle）。生成時に自動チェックを開始し、About とメニューから共有する。
    @StateObject private var updater = UpdaterController()

    /// About ウィンドウの識別子（標準 About を置換し openWindow(id:) で開く）。
    static let aboutWindowID = "about"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(gainForgeViewer)
                .frame(minWidth: 560, minHeight: 480)
        }
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands(updater: updater)
        }

        // アプリ情報（別ウィンドウ・単一インスタンス）。標準 About を置き換える。
        // 起動時は自動表示せず、メニュー「JPPhotoTools について」でのみ開く。
        Window("JPPhotoTools について", id: Self.aboutWindowID) {
            AboutView()
                .environmentObject(updater)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        // 比較ビューワ（別ウィンドウ・単一インスタンス）。GainForge タブの行ダブルクリックで
        // モジュール内から openWindow(id:) が呼ばれ、同じ gainForgeViewer に内容がセットされる。
        Window("比較ビューワ", id: GainForgeTab.viewerWindowID) {
            ViewerView()
                .environmentObject(gainForgeViewer)
                // 本体ウィンドウと同じく黒基調で固定する。
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

/// アプリメニューのカスタムコマンド。標準の「About」を自前の About ウィンドウに置換し、
/// その直後に「更新を確認」を追加する。
/// （openWindow と updater へアクセスするため、.commands クロージャから分離した Commands 型にする）
private struct AppCommands: Commands {
    @ObservedObject var updater: UpdaterController
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // 標準「JPPhotoTools について」を専用 About ウィンドウに差し替える。
        CommandGroup(replacing: .appInfo) {
            Button("JPPhotoTools について") {
                openWindow(id: JPPhotoToolsApp.aboutWindowID)
            }
        }
        // About の直後に「更新を確認」を並べる。
        CommandGroup(after: .appInfo) {
            Button("更新を確認…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
    }
}
