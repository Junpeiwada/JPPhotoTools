import Foundation
import CoreGraphics

/// 1 ファイルの変換結果。
public struct ConversionResult: Sendable, Equatable {
    /// 出力された JPEG の URL。
    public let outputURL: URL
    /// 変換前のバイト数。
    public let inputBytes: Int
    /// 変換後のバイト数。
    public let outputBytes: Int
    /// 出力 JPEG の実ピクセル寸法（Orientation 焼き込み・リサイズ後の正立寸法）。
    public let outputPixelSize: CGSize

    public init(outputURL: URL, inputBytes: Int, outputBytes: Int, outputPixelSize: CGSize) {
        self.outputURL = outputURL
        self.inputBytes = inputBytes
        self.outputBytes = outputBytes
        self.outputPixelSize = outputPixelSize
    }

    /// 出力 / 入力のサイズ比（0.0–1.0）。入力サイズ不明時は nil。
    public var sizeRatio: Double? {
        guard inputBytes > 0 else { return nil }
        return Double(outputBytes) / Double(inputBytes)
    }
}
