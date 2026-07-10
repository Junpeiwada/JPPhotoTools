// JpegResizer.swift
// 画像をアスペクト比を維持したまま高品質にリサイズし、JPEG として書き出す中核 API。
//
// 方式: Core Image の CILanczosScaleTransform（最高品質リサンプラ）で等方縮小し、
// ImageIO（CGImageDestination）で JPEG エンコードする。Exif は全て除去し、Orientation は
// 除去前にピクセルへ焼き込んで正立させる。ICC カラープロファイルは画質維持のため保持する。

import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// JpegResizer の公開 API 名前空間。
public enum JpegResizer {

    // MARK: - 変換

    /// 画像を JPEG へリサイズ変換する（縮小のみ・アスペクト比維持）。
    ///
    /// - Important: `output` の親ディレクトリは呼び出し側で事前に用意すること。
    ///   存在しないと `CGImageDestinationCreateWithURL` が nil を返し `.destinationCreateFailed` になる。
    ///
    /// - Parameters:
    ///   - input: 入力画像の URL（JPEG / PNG / HEIC / TIFF など ImageIO が読める形式）。
    ///   - output: 出力 JPEG の URL。
    ///   - quality: JPEG 圧縮品質（0.0–1.0、内部でクランプ）。
    ///   - resize: リサイズ方式（既定 `.original` はリサイズなし）。アスペクト比を維持し **縮小のみ**
    ///     行う（原寸超えは原寸のまま）。再サンプルは `CILanczosScaleTransform`（最高品質）で行う。
    ///   - overwrite: 出力先に既存ファイルがある場合に上書きするか。false のときに既存が
    ///     あれば `.outputExists` を投げる（事前計画外の予期せぬ上書きを防ぐ安全弁）。
    /// - Returns: 変換結果（サイズ・出力寸法）。
    @discardableResult
    public static func convert(
        input: URL,
        output: URL,
        quality: Double = 0.85,
        resize: ResizeMode = .original,
        overwrite: Bool = false
    ) throws -> ConversionResult {
        let q = max(0.0, min(1.0, quality))
        try ensureWritable(output, overwrite: overwrite)

        guard let src = CGImageSourceCreateWithURL(input as CFURL, nil) else {
            throw JpegResizerError.cannotReadSource(input)
        }
        // Exif の向き（Orientation）はピクセルへ焼き込むために取得する（このあと向き情報は書かない）。
        let props = (CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]) ?? [:]
        let orientation = (props[kCGImagePropertyOrientation] as? UInt32).map { Int32($0) } ?? 1

        // 入力の色空間（ICC）を保持するため元 CGImage から取得する。RGB 以外（CMYK/グレースケール等）は
        // RGBA8 描画と噛み合わないため sRGB へ寄せる。
        guard let inputCG = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw JpegResizerError.imageUnreadable(input)
        }
        let colorSpace: CGColorSpace = {
            if let cs = inputCG.colorSpace, cs.model == .rgb { return cs }
            return CGColorSpace(name: CGColorSpace.sRGB)!
        }()

        // 既にデコード済みの inputCG を CIImage 化して二重デコードを避ける。
        // CIImage(cgImage:) は Orientation 未適用の生ピクセルを返すため、下の手動焼き込みと整合する。
        var ci = CIImage(cgImage: inputCG)
        // Exif Orientation を実ピクセルへ焼き込んで正立させる（見た目の向きを保持したまま向き情報を捨てる）。
        ci = ci.oriented(forExifOrientation: orientation)

        // リサイズ計画（縮小のみ・アスペクト維持）。等倍なら再サンプルを一切かけない。
        // 基準寸法は Orientation 焼き込み後の正立寸法（表示寸法）に一致する。
        let resizeTarget = ResizePlanner.targetSize(original: ci.extent.size, mode: resize)
        if let resizeTarget {
            ci = lanczosResized(ci, scale: resizeTarget.width / ci.extent.width)
        }

        // 入力の色空間で CGImage に焼く（ICC 保持）。作業空間は拡張リニア sRGB にして、
        // Lanczos をリニア光で高品質に補間しつつ広色域（Display P3 等）を丸めない。
        let rect = ci.extent.integral
        guard !rect.isEmpty, !rect.isInfinite,
              let cg = sharedContext.createCGImage(ci, from: rect, format: .RGBA8, colorSpace: colorSpace) else {
            throw JpegResizerError.imageUnreadable(input)
        }

        // JPEG として書き出す。Exif は一切引き継がず品質のみ指定する（プライバシー配慮・配布用途）。
        // ICC は cg の colorSpace として自動的に埋め込まれる。Orientation は焼き込み済みのため書かない。
        guard let dst = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw JpegResizerError.destinationCreateFailed(output)
        }
        let jpegProps: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: q]
        CGImageDestinationAddImage(dst, cg, jpegProps as CFDictionary)
        guard CGImageDestinationFinalize(dst) else {
            throw JpegResizerError.finalizeFailed(output)
        }

        return ConversionResult(
            outputURL: output,
            inputBytes: fileSize(input),
            outputBytes: fileSize(output),
            outputPixelSize: CGSize(width: cg.width, height: cg.height)
        )
    }

    // MARK: - リサイズ（高品質リサンプル）

    /// リサンプル用の共有コンテキスト。作業空間を拡張リニア sRGB にして、Lanczos をリニア光で
    /// 補間しつつ広色域（Display P3）を維持する。変換ごとに作らず一度だけ生成する（バッチの無駄を避ける）。
    private static let sharedContext: CIContext = {
        let working = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) ?? CGColorSpaceCreateDeviceRGB()
        return CIContext(options: [.workingColorSpace: working])
    }()

    /// `CILanczosScaleTransform`（Core Image 最高品質のリサンプラ）で等方スケールした CIImage を返す。
    /// アスペクト比は変えない（`inputAspectRatio` = 1.0）。フィルタ生成に失敗したときはアフィン変換で代替。
    private static func lanczosResized(_ image: CIImage, scale: CGFloat) -> CIImage {
        guard scale != 1.0, let f = CIFilter(name: "CILanczosScaleTransform") else {
            return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        f.setValue(image, forKey: kCIInputImageKey)
        f.setValue(scale, forKey: kCIInputScaleKey)
        f.setValue(1.0, forKey: kCIInputAspectRatioKey)
        return f.outputImage ?? image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    // MARK: - ユーティリティ

    /// 出力先が書き込み可能か確認する。上書き不許可で既存ファイルがあれば `.outputExists` を投げる。
    private static func ensureWritable(_ output: URL, overwrite: Bool) throws {
        if !overwrite, FileManager.default.fileExists(atPath: output.path) {
            throw JpegResizerError.outputExists(output)
        }
    }

    /// ファイルのバイト数を返す（取得不能時は 0）。
    public static func fileSize(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    /// 入力として受け付ける画像拡張子（小文字）。出力は常に JPEG。
    public static let supportedInputExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff",
    ]

    /// フォルダを再帰探索し、対応拡張子の画像 URL 一覧を返す。
    /// ファイル URL はそのまま 1 件返す。結果はパス順にソートする。
    public static func collectInputImages(_ url: URL) -> [URL] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue {
            return isSupportedImage(url) ? [url] : []
        }
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: nil) else { return [] }
        var result: [URL] = []
        for case let f as URL in en where isSupportedImage(f) {
            result.append(f)
        }
        return result.sorted { $0.path < $1.path }
    }

    private static func isSupportedImage(_ url: URL) -> Bool {
        supportedInputExtensions.contains(url.pathExtension.lowercased())
    }
}
