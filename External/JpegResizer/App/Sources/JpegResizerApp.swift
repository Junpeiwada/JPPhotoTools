import SwiftUI

@main
struct JpegResizerApp: App {
    @StateObject private var model = AppViewModel()

    /// ウィンドウフレームの自動保存キー。
    private static let frameAutosaveName = "JpegResizerMainWindow"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 500, minHeight: 460)
                .background(WindowFrameAutosave(name: Self.frameAutosaveName))
                .background(MainWindowTerminator())
        }
        .windowResizability(.contentMinSize)
        .commands {
            // 標準「About」の直後に「設定をリセット」を追加する。
            CommandGroup(after: .appInfo) {
                Button("設定をリセット") { model.resetSettings() }
                    .disabled(!model.canEditSettings)
            }
        }
    }
}
