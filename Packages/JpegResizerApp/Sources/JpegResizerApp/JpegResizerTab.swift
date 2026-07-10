import SwiftUI

/// 統合アプリ（JPPhotoTools）の「リサイズ書き出し」タブとして使う公開エントリ。
///
/// 元 JpegResizer アプリの `@main` が持っていた `AppViewModel` の生成・注入をこのタブが担い、
/// 中身は既存の `ContentView` をそのまま表示する。タブ本体はビューワ等の別ウィンドウを持たない。
public struct JpegResizerTab: View {
    @StateObject private var model = AppViewModel()

    public init() {}

    public var body: some View {
        ContentView()
            .environmentObject(model)
    }
}
