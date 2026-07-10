import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

/// 読み込み時の軽量な画像メタ取得（サムネ・寸法）。
/// すべて Sendable な値を返し、バックグラウンドで安全に実行できる。
///
/// GainForge / JpegResizer 双方の App 層に重複していたものを共通化。JpegResizer 版が
/// Exif Orientation 対応（サムネの正立化・寸法の幅高さ入れ替え）を含む上位互換だったため、
/// そちらを正として採用している（GainForge の用途はこの上位互換で完全に満たせる）。
public enum ImageProbe {

    /// 入力画像の縮小サムネイルを PNG データとして生成する（最大 `maxPixel` px）。
    /// NSImage は非 Sendable のため、ここでは Data（Sendable）を返して呼び出し側で復元する。
    /// `kCGImageSourceCreateThumbnailWithTransform` で Exif Orientation を適用し、正立で表示する。
    public static func thumbnailPNG(for url: URL, maxPixel: Int = 96) -> Data? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }

        let data = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dst, cg, nil)
        guard CGImageDestinationFinalize(dst) else { return nil }
        return data as Data
    }

    /// 画像の正立ピクセル寸法を取得する（デコードせずプロパティのみ参照）。
    /// Exif Orientation が 90°/270° 系（5–8）なら幅と高さを入れ替えて、表示上の寸法を返す。
    public static func pixelSize(for url: URL) -> CGSize? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let orientation = (props[kCGImagePropertyOrientation] as? UInt32) ?? 1
        // 5–8 は 90°/270° 回転を含み、正立時に幅高さが入れ替わる。
        if orientation >= 5 {
            return CGSize(width: h, height: w)
        }
        return CGSize(width: w, height: h)
    }
}
