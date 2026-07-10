import XCTest
import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
@testable import JpegResizerCore

/// 中核 `convert()` のラウンドトリップ検証。
/// 設計の要点（Exif 全除去・Orientation のピクセル焼き込み・ICC 保持・縮小実適用・出力寸法・上書き判定）を
/// 合成画像で実際に書き出して確認する。
final class JpegResizerConvertTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("JpegResizerConvertTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - 合成入力の生成

    /// 指定サイズ・Orientation・色空間・Exif UserComment を持つ JPEG を temp に書き出す。
    /// 返す URL の格納ピクセルは `storedWidth × storedHeight`（Orientation は適用前の値）。
    private func makeJPEG(name: String,
                          storedWidth: Int, storedHeight: Int,
                          orientation: Int = 1,
                          colorSpaceName: CFString = CGColorSpace.sRGB,
                          userComment: String? = "SECRET-EXIF") throws -> URL {
        let ctx = CIContext()
        let img = CIImage(color: CIColor(red: 0.2, green: 0.6, blue: 0.9))
            .cropped(to: CGRect(x: 0, y: 0, width: storedWidth, height: storedHeight))
        let cs = CGColorSpace(name: colorSpaceName)!
        let cg = ctx.createCGImage(img, from: img.extent, format: .RGBA8, colorSpace: cs)!
        let url = tmp.appendingPathComponent(name)
        let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        var props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.9,
            kCGImagePropertyOrientation: orientation,
        ]
        if let userComment {
            props[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifUserComment: userComment]
        }
        CGImageDestinationAddImage(dst, cg, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dst), "テスト用 JPEG の書き出しに失敗")
        return url
    }

    /// 出力プロパティ辞書を読む。
    private func properties(of url: URL) -> [CFString: Any] {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return [:] }
        return p
    }

    // MARK: - Orientation 焼き込み

    /// Orientation=6（90° 回転）の入力は、正立ピクセルへ焼き込まれ、出力に向き情報が残らない。
    /// 格納 4000×3000・orientation=6 は表示 3000×4000。リサイズなしなら出力も 3000×4000。
    func testOrientationBakedUprightAndStripped() throws {
        let input = try makeJPEG(name: "rot.jpg", storedWidth: 4000, storedHeight: 3000, orientation: 6)
        let output = tmp.appendingPathComponent("rot-out.jpg")
        let r = try JpegResizer.convert(input: input, output: output, quality: 0.8, resize: .original)

        // 出力寸法は正立（幅高さが入れ替わっている）。
        XCTAssertEqual(r.outputPixelSize, CGSize(width: 3000, height: 4000))

        let props = properties(of: output)
        // 向き情報は無い、もしくは 1（正立）。二重回転しない。
        let outOrientation = (props[kCGImagePropertyOrientation] as? UInt32) ?? 1
        XCTAssertEqual(outOrientation, 1, "Orientation は焼き込み済みで正立(=1)であること")
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 3000)
        XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, 4000)
    }

    // MARK: - Exif 除去

    /// 元の Exif（UserComment 等）は出力から除去される。
    func testExifStripped() throws {
        let input = try makeJPEG(name: "exif.jpg", storedWidth: 800, storedHeight: 600,
                                 orientation: 1, userComment: "SECRET-EXIF")
        let output = tmp.appendingPathComponent("exif-out.jpg")
        try JpegResizer.convert(input: input, output: output, quality: 0.8)

        let props = properties(of: output)
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        // ImageIO が自動付与する PixelXDimension 等は許容するが、元の UserComment は消えていること。
        XCTAssertNil(exif?[kCGImagePropertyExifUserComment], "元の Exif UserComment が残存している")
        XCTAssertNil(props[kCGImagePropertyGPSDictionary], "GPS は残さない")
        XCTAssertNil(props[kCGImagePropertyTIFFDictionary], "TIFF(機種等)は残さない")
    }

    // MARK: - ICC 保持

    /// Display P3 入力の出力は sRGB へ落ちず、広色域プロファイルを保持する。
    func testICCProfilePreservedForP3() throws {
        let input = try makeJPEG(name: "p3.jpg", storedWidth: 800, storedHeight: 600,
                                 colorSpaceName: CGColorSpace.displayP3)
        let output = tmp.appendingPathComponent("p3-out.jpg")
        try JpegResizer.convert(input: input, output: output, quality: 0.8)

        guard let src = CGImageSourceCreateWithURL(output as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let name = cg.colorSpace?.name as String? else {
            return XCTFail("出力の色空間を取得できない")
        }
        XCTAssertTrue(name.contains("P3"), "P3 プロファイルが保持されていない: \(name)")
    }

    // MARK: - 縮小の実適用

    /// `fitWidth` 指定で実際に縮小され、出力寸法・格納ピクセルが目標幅になる。
    func testFitWidthActuallyDownscales() throws {
        let input = try makeJPEG(name: "big.jpg", storedWidth: 4000, storedHeight: 3000)
        let output = tmp.appendingPathComponent("big-out.jpg")
        let r = try JpegResizer.convert(input: input, output: output, resize: .fitWidth(2000))

        XCTAssertEqual(r.outputPixelSize, CGSize(width: 2000, height: 1500))
        let props = properties(of: output)
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 2000)
        XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, 1500)
        // 縮小されているので出力バイト数は入力より小さい傾向（少なくとも 0 でない）。
        XCTAssertGreaterThan(r.outputBytes, 0)
    }

    /// 原寸を超える指定は拡大せず、出力は原寸のまま。
    func testDoesNotUpscale() throws {
        let input = try makeJPEG(name: "small.jpg", storedWidth: 800, storedHeight: 600)
        let output = tmp.appendingPathComponent("small-out.jpg")
        let r = try JpegResizer.convert(input: input, output: output, resize: .fitWidth(4000))
        XCTAssertEqual(r.outputPixelSize, CGSize(width: 800, height: 600))
    }

    // MARK: - 上書き判定

    /// 既存出力があり overwrite=false なら `.outputExists` を投げ、ファイルを書き換えない。
    func testOverwriteGuardThrows() throws {
        let input = try makeJPEG(name: "ow.jpg", storedWidth: 400, storedHeight: 300)
        let output = tmp.appendingPathComponent("ow-out.jpg")
        try Data("existing".utf8).write(to: output)

        XCTAssertThrowsError(try JpegResizer.convert(input: input, output: output, overwrite: false)) { error in
            guard case JpegResizerError.outputExists = error else {
                return XCTFail("outputExists 以外が投げられた: \(error)")
            }
        }
        // 既存内容が保たれている（書き換えられていない）。
        XCTAssertEqual(try Data(contentsOf: output), Data("existing".utf8))
    }

    /// overwrite=true なら既存を置き換えて変換できる。
    func testOverwriteAllowedReplaces() throws {
        let input = try makeJPEG(name: "ow2.jpg", storedWidth: 400, storedHeight: 300)
        let output = tmp.appendingPathComponent("ow2-out.jpg")
        try Data("existing".utf8).write(to: output)

        let r = try JpegResizer.convert(input: input, output: output, overwrite: true)
        XCTAssertEqual(r.outputPixelSize, CGSize(width: 400, height: 300))
        XCTAssertGreaterThan(r.outputBytes, "existing".count, "実 JPEG で置き換わっているはず")
    }
}
