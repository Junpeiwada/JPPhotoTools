import SwiftUI

/// アプリ全体のカラースキーム（黒基調・ダーク固定）。
///
/// 実体の色値は `Assets.xcassets` のカラーセットで管理し、ここでは名前参照だけを
/// 一元化する（Asset + enum ハイブリッド）。`Color("Surface")` のような文字列直参照を
/// 各ビューに散らさず、`Palette.surface` 経由でのみ触ることで、名前の打ち間違いを
/// コンパイル時に近い形で防ぎ、色の微調整は Asset 側だけで完結させる。
///
/// 差し色は「機能別マルチ」方式。TabView の選択タブに応じて `tint(_:)` で各タブの
/// 署名色を environment に流すため（`ContentView`）、別モジュールのタブ（GainForge /
/// JpegResizer）配下のコントロールにもタブ色が伝播する。
enum Palette {
    // MARK: - ニュートラル基盤（奥行きは面を段階的に持ち上げて表現）
    /// ウィンドウ最背面。
    static let base = Color("Base")
    /// パネル・カード面。
    static let surface = Color("Surface")
    /// 浮いた要素・ホバー面。
    static let elevated = Color("Elevated")
    /// 境界線・区切り。
    static let stroke = Color("Stroke")
    /// 主要テキスト（旧 `.primary` 相当）。
    static let text1 = Color("Text1")
    /// 補助テキスト（旧 `.secondary` 相当）。
    static let text2 = Color("Text2")
    /// プレースホルダ・最も弱いテキスト（旧 `.tertiary` 相当）。
    static let text3 = Color("Text3")

    // MARK: - 状態色（黒背景で沈まないよう彩度を調整。差し色とは役割を分離）
    /// 成功 / ok / done（旧 `.green`）。
    static let success = Color("Success")
    /// 警告（旧 `.orange`）。
    static let warning = Color("Warning")
    /// エラー / Del（旧 `.red`）。
    static let danger = Color("Danger")
    /// 情報 / RAW / 選択ピン（旧 `.blue`）。
    static let info = Color("Info")
    /// 無効 / skip（旧 `.gray`）。
    static let neutral = Color("Neutral")

    // MARK: - タブ署名色（機能別マルチ差し色）
    /// 取り込み・整理タブ（青）。
    static let tabOrganize = Color("TabOrganize")
    /// HDR 変換タブ（紫）。
    static let tabHDR = Color("TabHDR")
    /// リサイズ書き出しタブ（緑）。
    static let tabResize = Color("TabResize")
    /// ジオタグタブ（琥珀）。
    static let tabGeo = Color("TabGeo")
}
