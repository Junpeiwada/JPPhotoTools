import Foundation
import CoreGraphics
import JpegResizerCore
import PhotoKitShared

/// JpegResizer 固有の行付加情報（元寸法・出力寸法）。
struct JpegResizerExtra: Equatable, Sendable {
    var pixelSize: CGSize?
    var outputPixelSize: CGSize?
}

/// JpegResizer 固有の変換設定のスナップショット（バッチ開始・probe 時に確定する）。
struct JpegResizerSettings: Sendable {
    var quality: Double
    var resize: ResizeMode
}

/// JpegResizer の機能定義。共通シェル `AppViewModel` へ「入力収集・probe・変換・出力計画」を注入する。
struct JpegResizerFeature: FeatureShell {
    typealias Extra = JpegResizerExtra
    typealias Settings = JpegResizerSettings

    var initialExtra: JpegResizerExtra { JpegResizerExtra(pixelSize: nil, outputPixelSize: nil) }

    // macOS 既定の APFS は case-insensitive。`Photo.jpg` と `photo.jpg` を同一出力先とみなして
    // 連番回避し、取り違え・上書き事故を防ぐ（移行前 JpegResizerCore.OutputPlanner の挙動を維持）。
    var outputIsCaseInsensitive: Bool { true }

    func collectInputs(_ urls: [URL]) -> [URL] {
        urls.flatMap { JpegResizer.collectInputImages($0) }
    }

    func probe(_ url: URL, settings: JpegResizerSettings) -> ProbeResult<JpegResizerExtra> {
        let size = JpegResizer.fileSize(url)
        let pixelSize = ImageProbe.pixelSize(for: url)
        let png = ImageProbe.thumbnailPNG(for: url)
        let extra = JpegResizerExtra(pixelSize: pixelSize, outputPixelSize: nil)
        return ProbeResult(inputBytes: size, thumbnailPNG: png, extra: extra, existingOutput: nil)
    }

    func convert(
        input: URL, output: URL, overwrite: Bool, settings: JpegResizerSettings
    ) throws -> ConversionSuccess<JpegResizerExtra> {
        do {
            let r = try JpegResizer.convert(
                input: input, output: output, quality: settings.quality,
                resize: settings.resize, overwrite: overwrite)
            // 出力寸法は変換完了時に resultExtra で該当行へ反映する（テーブルの寸法列の出力側）。
            // pixelSize（元寸法）は probe 済みだが Extra は上書きになるため、両方を持ち直す。
            let extra = JpegResizerExtra(pixelSize: ImageProbe.pixelSize(for: input),
                                         outputPixelSize: r.outputPixelSize)
            return ConversionSuccess(outputURL: r.outputURL, outputBytes: r.outputBytes,
                                     inputBytes: r.inputBytes, resultExtra: extra)
        } catch let e as JpegResizerError {
            if case .outputExists = e { throw FeatureConversionError.blocked(e.localizedDescription) }
            throw FeatureConversionError.failed(e.localizedDescription)
        } catch {
            throw FeatureConversionError.failed(error.localizedDescription)
        }
    }

    func outputFileName(stem: String, index: Int, settings: JpegResizerSettings) -> String {
        // JpegResizerCore.OutputPlanner の命名規則（`<stem>-resized.jpg` / `<stem>-resized_N.jpg`）に合わせる。
        // `OutputPlanner` は PhotoKitShared にも同名の型があるため、モジュール名で明示的に修飾する。
        let base = stem + JpegResizerCore.OutputPlanner.suffix
        return index <= 0
            ? "\(base).\(JpegResizerCore.OutputPlanner.outputExtension)"
            : "\(base)_\(index).\(JpegResizerCore.OutputPlanner.outputExtension)"
    }
}
