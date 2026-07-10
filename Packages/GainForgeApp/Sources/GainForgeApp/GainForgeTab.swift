import SwiftUI
import PhotoKitShared

/// 統合アプリ（JPPhotoTools）の GainForge タブとして埋め込むための公開エントリ View。
/// 内部で AppViewModel（タブ固有の状態）を保持し、既存の ContentView をそのまま表示する。
///
/// 比較ビューワは別の Window シーンで開くため、ViewerModel は GainForgeTab 内部では保持せず、
/// 統合アプリのルートから環境（.environmentObject）で受け取り、ビューワ Window シーンと
/// 同一インスタンスを共有する。統合アプリ側の結線イメージ:
///
/// ```swift
/// @main
/// struct JPPhotoToolsApp: App {
///     // ルートで 1 つだけ保持し、タブとビューワ Window の両方へ注入する。
///     @StateObject private var gainForgeViewer = ViewerModel()
///
///     var body: some Scene {
///         WindowGroup {
///             TabView {
///                 GainForgeTab()
///                     .environmentObject(gainForgeViewer)   // ← タブへ注入
///                 // 他のタブ...
///             }
///         }
///         // 行のダブルクリックで openWindow(id: GainForgeTab.viewerWindowID) される。
///         Window("比較ビューワ", id: GainForgeTab.viewerWindowID) {
///             ViewerView()
///                 .environmentObject(gainForgeViewer)       // ← 同一インスタンスを注入
///         }
///     }
/// }
/// ```
public struct GainForgeTab: View {
    @StateObject private var model = GainForgeViewModel()
    /// 比較ビューワの共有状態。統合アプリのルートで保持したものを環境から受け取り、
    /// ビューワ Window シーンと同一インスタンスを共有する。
    @EnvironmentObject private var viewer: ViewerModel

    /// 比較ビューワウィンドウの識別子（統合アプリ側が openWindow(id:) で前面化する）。
    public static let viewerWindowID = "gainForgeViewer"

    public init() {}

    public var body: some View {
        ContentView()
            .environmentObject(model)
            .environmentObject(viewer)
    }
}
