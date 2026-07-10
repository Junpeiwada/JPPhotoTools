import Foundation
import AppKit
import GainForgeCore
import PhotoKitShared

/// GainForge タブの ViewModel。共通シェル `AppViewModel<GainForgeFeature>` を継承し、
/// 品質・出力先・SDR画像・リサイズ設定の保持（UserDefaults 永続化）と `makeSettings()` の提供、
/// ML/LUT 降格通知（バッチ開始前・起動中一度だけ）を担う。
@MainActor
final class GainForgeViewModel: AppViewModel<GainForgeFeature> {

    // MARK: - 設定（UserDefaults に永続化）
    @Published var quality: Double {
        didSet { defaults.set(quality, forKey: Keys.quality) }
    }
    @Published var outputMode: OutputMode {
        didSet { defaults.set(outputMode == .customFolder, forKey: Keys.outputIsCustom) }
    }
    @Published var customFolder: URL? {
        didSet { defaults.set(customFolder?.path, forKey: Keys.customFolderPath) }
    }
    /// ゲインマップ無し（SDR）入力の変換方式。HDR 入力（ゲインマップ付き）には影響しない。
    @Published var sdrMode: SDRConversion {
        didSet { defaults.set(sdrMode.rawValue, forKey: Keys.sdrMode) }
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

    /// `.hdrML` 選択時に LUT を読めず `.hdrCurve` へ降格した旨を、この起動中に通知済みか
    /// （降格は全ファイル共通のためバッチのたびに出さず一度だけ知らせる）。
    private var didNotifyMLFallback = false

    private let defaults: UserDefaults
    private enum Keys {
        static let quality = "gf.quality"
        static let outputIsCustom = "gf.outputIsCustom"
        static let customFolderPath = "gf.customFolderPath"
        static let sdrMode = "gf.sdrMode"
        static let resizeKind = "gf.resizeKind"
        static let resizeMegapixels = "gf.resizeMegapixels"
        static let resizeWidth = "gf.resizeWidth"
        static let resizeHeight = "gf.resizeHeight"
    }

    /// 設定の初期値。初回起動時の既定値と「設定リセット」の戻り先を一元管理する。
    enum Defaults {
        static let quality = 0.6
        static let outputMode = OutputMode.sameFolder
        // 既定は従来挙動（SDR 画像は SDR HEIC で保存）。HDR 補正はユーザーが明示選択する。
        static let sdrMode = SDRConversion.sdr
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
        self.outputMode = defaults.bool(forKey: Keys.outputIsCustom) ? .customFolder : .sameFolder
        self.sdrMode = defaults.string(forKey: Keys.sdrMode)
            .flatMap(SDRConversion.init(rawValue:)) ?? Defaults.sdrMode
        self.resizeKind = defaults.string(forKey: Keys.resizeKind)
            .flatMap(ResizeKind.init(rawValue:)) ?? Defaults.resizeKind
        self.resizeMegapixels = (defaults.object(forKey: Keys.resizeMegapixels) as? Double) ?? Defaults.resizeMegapixels
        self.resizeWidth = (defaults.object(forKey: Keys.resizeWidth) as? Int) ?? Defaults.resizeWidth
        self.resizeHeight = (defaults.object(forKey: Keys.resizeHeight) as? Int) ?? Defaults.resizeHeight
        // 復元したフォルダが実在しなければ「未選択」に戻す（削除済みパスを使い回さない）。
        if let p = defaults.string(forKey: Keys.customFolderPath) {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: p, isDirectory: &isDir) && isDir.boolValue
            self.customFolder = exists ? URL(fileURLWithPath: p) : nil
        } else {
            self.customFolder = nil
        }
        super.init(feature: GainForgeFeature())
    }

    override func makeSettings() -> GainForgeSettings {
        GainForgeSettings(quality: quality, sdrMode: sdrMode, resize: resizeMode,
                          outputMode: outputMode, customFolder: customFolder)
    }

    // MARK: - 変換開始前の ML/LUT 降格通知

    /// バッチ開始前（出力計画・上書き確認の後、実変換の直前）に共通シェルから呼ばれる。
    /// `.hdrML` を選んでいるのに LUT を読み込めず、かつ今回**実際に変換する**行に降格影響のある行
    /// （ゲインマップ無し）を含むときだけ、起動中一度だけ通知する。
    /// `extras` は共通シェルが確定した変換対象行の付加情報なので、上書き確認でキャンセルした場合は
    /// そもそも呼ばれず、通知も `didNotifyMLFallback` の消費も起きない（旧実装の挙動と一致）。
    override func willStartConversion(extras: [GainForgeExtra]) {
        if sdrMode == .hdrML, !GainForge.isMLGainLUTAvailable, !didNotifyMLFallback,
           extras.contains(where: { $0.gainMap != .present }) {
            didNotifyMLFallback = true
            presentMLFallbackNotice()
        }
    }

    /// `.hdrML`（ML/LUT）を選んでいるが LUT を読み込めず、明部加重カーブ（`.hdrCurve`）へ
    /// 自動降格することを知らせる（この起動中一度だけ）。ゲインマップ無し SDR 画像のみに作用し、
    /// ゲインマップ付き画像（生転写）には影響しない。
    private func presentMLFallbackNotice() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "HDR補正（ML/LUT）の学習データを読み込めません"
        alert.informativeText = "ゲインマップの無い SDR 画像は、明部加重カーブ（HDR補正（カーブ））で"
            + "代替して補正します。ゲインマップ付きの画像には影響しません。"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - 設定リセット

    /// 設定値（品質・出力先・指定フォルダ・SDR画像・リサイズ方式・各寸法）を初期値に戻す。
    /// 一覧やウィンドウ位置・サイズには影響しない。didSet 経由で永続化も更新される。
    func resetSettings() {
        guard canEditSettings else { return }
        quality = Defaults.quality
        outputMode = Defaults.outputMode
        customFolder = nil
        sdrMode = Defaults.sdrMode
        resizeKind = Defaults.resizeKind
        resizeMegapixels = Defaults.resizeMegapixels
        resizeWidth = Defaults.resizeWidth
        resizeHeight = Defaults.resizeHeight
    }
}
