import Foundation
import GainForgeCore
import PhotoKitShared

/// GainForge 固有の変換設定のスナップショット（バッチ開始・probe 時に確定する）。
struct GainForgeSettings: Sendable {
    var quality: Double
    var sdrMode: SDRConversion
    var resize: ResizeMode
    var outputMode: OutputMode
    var customFolder: URL?
}

/// GainForge の機能定義。共通シェル `AppViewModel` へ「入力収集・probe・変換・出力計画」を注入する。
struct GainForgeFeature: FeatureShell {
    typealias Extra = GainForgeExtra
    typealias Settings = GainForgeSettings

    var initialExtra: GainForgeExtra { GainForgeExtra(gainMap: .checking) }

    func collectInputs(_ urls: [URL]) -> [URL] {
        urls.flatMap { GainForge.collectInputImages($0) }
    }

    func probe(_ url: URL, settings: GainForgeSettings) -> ProbeResult<GainForgeExtra> {
        let size = GainForge.fileSize(url)
        let hasGain = GainForge.hasGainMap(url)
        let png = ImageProbe.thumbnailPNG(for: url)
        let extra = GainForgeExtra(gainMap: hasGain ? .present : .absent)

        let existing = ExistingOutputFinder.find(
            input: url, outputMode: settings.outputMode, customFolder: settings.customFolder,
            fileExists: { FileManager.default.fileExists(atPath: $0.path) })
        let existingOutput = existing.map { (url: $0, bytes: GainForge.fileSize($0)) }

        return ProbeResult(inputBytes: size, thumbnailPNG: png, extra: extra, existingOutput: existingOutput)
    }

    func convert(
        input: URL, output: URL, overwrite: Bool, settings: GainForgeSettings
    ) throws -> ConversionSuccess<GainForgeExtra> {
        do {
            let r = try GainForge.convert(
                input: input, output: output, quality: settings.quality,
                force: true, overwrite: overwrite, sdrMode: settings.sdrMode,
                resize: settings.resize)
            return ConversionSuccess(outputURL: r.outputURL, outputBytes: r.outputBytes, inputBytes: r.inputBytes)
        } catch let e as GainForgeError {
            if case .outputExists = e { throw FeatureConversionError.blocked(e.localizedDescription) }
            throw FeatureConversionError.failed(e.localizedDescription)
        } catch {
            throw FeatureConversionError.failed(error.localizedDescription)
        }
    }

    func outputDirectory(for input: URL, settings: GainForgeSettings) -> URL {
        switch settings.outputMode {
        case .sameFolder:   return input.deletingLastPathComponent()
        case .customFolder: return settings.customFolder ?? input.deletingLastPathComponent()
        }
    }

    func outputFileName(stem: String, index: Int, settings: GainForgeSettings) -> String {
        index <= 0 ? "\(stem).heic" : "\(stem)_\(index).heic"
    }
}
