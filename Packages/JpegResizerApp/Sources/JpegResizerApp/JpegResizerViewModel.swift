import Foundation
import CoreGraphics
import JpegResizerCore
import PhotoKitShared

/// JpegResizer タブの ViewModel。共通シェル `AppViewModel<JpegResizerFeature>` を継承し、
/// 品質・リサイズ設定の保持（UserDefaults 永続化）と `makeSettings()` の提供のみを担う。
@MainActor
final class JpegResizerViewModel: AppViewModel<JpegResizerFeature> {

    // MARK: - 設定（UserDefaults に永続化）
    @Published var quality: Double {
        didSet { defaults.set(quality, forKey: Keys.quality) }
    }

    // MARK: - リサイズ設定
    // 方式（種別）と各方式の数値を別々に保持・永続化する。方式を切り替えても各値を覚えておき、
    // 変換時に `resizeMode`（ResizeMode）へ組み立てる。全経路で縮小のみ・アスペクト維持。
    @Published var resizeKind: ResizeKind {
        didSet { defaults.set(resizeKind.rawValue, forKey: Keys.resizeKind) }
    }
    @Published var resizeMegapixels: Double {
        didSet { defaults.set(resizeMegapixels, forKey: Keys.resizeMegapixels) }
    }
    @Published var resizeWidth: Int {
        didSet { defaults.set(resizeWidth, forKey: Keys.resizeWidth) }
    }
    @Published var resizeHeight: Int {
        didSet { defaults.set(resizeHeight, forKey: Keys.resizeHeight) }
    }

    /// UI の種別＋数値から Core の `ResizeMode` を組み立てる（変換時に参照）。
    var resizeMode: ResizeMode {
        switch resizeKind {
        case .original:   return .original
        case .megapixels: return .megapixels(resizeMegapixels)
        case .width:      return .fitWidth(resizeWidth)
        case .height:     return .fitHeight(resizeHeight)
        }
    }

    /// 現在のリサイズ設定で、ある元寸法がどの出力寸法になるかを予測する（テーブルのプレビュー用）。
    /// 縮小にならない（原寸維持）なら元寸法をそのまま返す。
    func plannedOutputSize(for original: CGSize) -> CGSize {
        ResizePlanner.targetSize(original: original, mode: resizeMode) ?? original
    }

    private let defaults: UserDefaults
    private enum Keys {
        static let quality = "jr.quality"
        static let resizeKind = "jr.resizeKind"
        static let resizeMegapixels = "jr.resizeMegapixels"
        static let resizeWidth = "jr.resizeWidth"
        static let resizeHeight = "jr.resizeHeight"
    }

    /// 設定の初期値。初回起動時の既定値と「設定リセット」の戻り先を一元管理する。
    enum Defaults {
        static let quality = 0.85
        // 既定はリサイズなし。各方式の初期値は一般的な値（切替時に個別に覚える）。
        static let resizeKind = ResizeKind.original
        static let resizeMegapixels = 8.0
        static let resizeWidth = 3840
        static let resizeHeight = 2160
    }

    /// - Parameter defaults: 設定の永続化先。テストでは専用 suite を注入する。
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let q = defaults.object(forKey: Keys.quality) as? Double
        self.quality = q ?? Defaults.quality
        self.resizeKind = defaults.string(forKey: Keys.resizeKind)
            .flatMap(ResizeKind.init(rawValue:)) ?? Defaults.resizeKind
        self.resizeMegapixels = (defaults.object(forKey: Keys.resizeMegapixels) as? Double) ?? Defaults.resizeMegapixels
        self.resizeWidth = (defaults.object(forKey: Keys.resizeWidth) as? Int) ?? Defaults.resizeWidth
        self.resizeHeight = (defaults.object(forKey: Keys.resizeHeight) as? Int) ?? Defaults.resizeHeight
        super.init(feature: JpegResizerFeature())
    }

    override func makeSettings() -> JpegResizerSettings {
        JpegResizerSettings(quality: quality, resize: resizeMode)
    }

    // MARK: - 設定リセット

    /// 設定値（品質・リサイズ方式・各寸法）を初期値に戻す。
    /// 一覧やウィンドウ位置・サイズには影響しない。didSet 経由で永続化も更新される。
    func resetSettings() {
        guard canEditSettings else { return }
        quality = Defaults.quality
        resizeKind = Defaults.resizeKind
        resizeMegapixels = Defaults.resizeMegapixels
        resizeWidth = Defaults.resizeWidth
        resizeHeight = Defaults.resizeHeight
    }
}
