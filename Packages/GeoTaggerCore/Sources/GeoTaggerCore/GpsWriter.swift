import Foundation
import ImageIO

public enum GpsWriteError: Error, Sendable {
    case cannotOpenSource(URL)
    case writeFailed(URL, String)
}

/// ImageIO（CGImageDestinationCopyImageSource）による無劣化メタデータ書き込み。
/// 画素は再エンコードせず、GPS / 日時タグのみを既存メタデータへ反映する。
///
/// 実装上の重要な注意（実写真での検証で判明した ImageIO の制約。詳細は完了報告を参照）:
/// - `CGImageMetadataTagCreate` + `CGImageDestinationCopyImageSource(metadata:)` は、
///   既存に同名タグがあるファイルに対して単純に `SetTagWithPath` するだけでは値が反映
///   されない（`CGImageMetadataSetTagWithPath` は true を返すが実体は変わらない）。
///   `CGImageMetadataRemoveTagWithPath` で明示的に既存タグを削除してから再設定することで
///   確実に反映される。
/// - `DateTimeOriginal` は上記の remove→再設定でも反映されないことがある一方、
///   専用キー `kCGImageDestinationDateTime` を使うと確実に反映される。ただし
///   `kCGImageDestinationMetadata` と排他のため、GPS/Offset 書き込みとは別の
///   `CGImageDestinationCopyImageSource` 呼び出し（2 段階）に分ける必要がある。
/// - 上記のどちらの方式でも、Sony 機の HDR 撮影による MPF 形式 Gain Map
///   （JPEG 内の補助画像）が壊れる（`MPImageType` が `Undefined` 化）。これは
///   ImageIO 側の制約で回避策が見つかっていない（画素本体・EXIF全体・GPS/日時は
///   無劣化で正しく書き込まれる。実害は HDR 表示の喪失のみで SDR 表示には影響しない）。
/// - `kCGImageDestinationDateTime` は DateTimeOriginal 以外の関連日時（ModifyDate 等）も
///   合わせて更新する仕様のため、IFD0/XMP の ModifyDate も書き込み時刻に変わる副作用がある。
public enum GpsWriter {
    /// 書き込むタグ（元 GeoTagger と同一）:
    /// - GPSLatitude + GPSLatitudeRef(N/S) / GPSLongitude + GPSLongitudeRef(E/W)
    /// - ele がある場合のみ GPSAltitude + GPSAltitudeRef(0/1)
    /// - localRewrite がある場合のみ DateTimeOriginal / OffsetTimeOriginal /
    ///   OffsetTime / OffsetTimeDigitized
    public static func write(_ request: GpsWriteRequest) throws {
        let url = request.url
        let fm = FileManager.default

        // Stage 1: GPS（+ Offset 系）を既存メタデータの remove→再設定方式で書き込む
        let stage1URL = tempURL(for: url, suffix: "stage1")
        defer { try? fm.removeItem(at: stage1URL) }
        try writeStage1(source: url, destination: stage1URL, request: request)

        // Stage 2: DateTimeOriginal のみ専用キーで書き込む（localRewrite がある場合のみ）
        let finalTempURL = tempURL(for: url, suffix: "stage2")
        if let rewrite = request.localRewrite {
            try writeStage2DateTime(source: stage1URL, destination: finalTempURL, localDto: rewrite.localDto)
        } else {
            // 日時書き換えなし: stage1 の結果をそのまま最終出力とする
            try? fm.removeItem(at: finalTempURL)
            try fm.copyItem(at: stage1URL, to: finalTempURL)
        }

        do {
            _ = try fm.replaceItemAt(url, withItemAt: finalTempURL)
        } catch {
            try? fm.removeItem(at: finalTempURL)
            throw GpsWriteError.writeFailed(url, error.localizedDescription)
        }
    }

    // MARK: - Stage 1: GPS / Offset

    private static func writeStage1(source url: URL, destination tempURL: URL, request: GpsWriteRequest) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw GpsWriteError.cannotOpenSource(url)
        }
        guard let type = CGImageSourceGetType(source) else {
            throw GpsWriteError.cannotOpenSource(url)
        }
        guard let metadata = CGImageMetadataCreateMutableCopy(
            CGImageSourceCopyMetadataAtIndex(source, 0, nil) ?? CGImageMetadataCreateMutable()
        ) else {
            throw GpsWriteError.writeFailed(url, "メタデータのコピーに失敗しました")
        }

        // 既存タグがある場合に上書きが反映されない問題を避けるため、対象パスを先に明示的に
        // 削除する（存在しない場合は false が返るが無視してよい）。
        for path in stage1RemovePaths(hasEle: request.ele != nil, hasOffset: request.localRewrite != nil) {
            _ = CGImageMetadataRemoveTagWithPath(metadata, nil, path as CFString)
        }

        try applyGpsTags(to: metadata, request: request)

        guard let destination = CGImageDestinationCreateWithURL(tempURL as CFURL, type, 1, nil) else {
            throw GpsWriteError.writeFailed(url, "一時ファイルの作成に失敗しました")
        }
        let destOptions: [CFString: Any] = [kCGImageDestinationMetadata: metadata]
        guard CGImageDestinationCopyImageSource(destination, source, destOptions as CFDictionary, nil) else {
            throw GpsWriteError.writeFailed(url, "GPS タグの書き込みに失敗しました")
        }
    }

    private static func stage1RemovePaths(hasEle: Bool, hasOffset: Bool) -> [String] {
        var paths = ["exif:GPSLatitude", "exif:GPSLatitudeRef", "exif:GPSLongitude", "exif:GPSLongitudeRef"]
        if hasEle {
            paths += ["exif:GPSAltitude", "exif:GPSAltitudeRef"]
        }
        if hasOffset {
            paths += ["exif:OffsetTimeOriginal", "exif:OffsetTime", "exif:OffsetTimeDigitized"]
        }
        return paths
    }

    private static func applyGpsTags(to metadata: CGMutableImageMetadata, request: GpsWriteRequest) throws {
        try setTagOrThrow(metadata, name: "GPSLatitude", value: abs(request.lat) as CFNumber, url: request.url)
        try setTagOrThrow(metadata, name: "GPSLatitudeRef", value: (request.lat >= 0 ? "N" : "S") as CFString, url: request.url)
        try setTagOrThrow(metadata, name: "GPSLongitude", value: abs(request.lon) as CFNumber, url: request.url)
        try setTagOrThrow(metadata, name: "GPSLongitudeRef", value: (request.lon >= 0 ? "E" : "W") as CFString, url: request.url)

        if let ele = request.ele {
            // GPSAltitude は CGImageMetadataTagCreate に CFNumber を渡すと整数に丸められる
            // （ImageIO の制約。GPSLatitude/Longitude は度分秒表現のため小数精度が保たれるが、
            // 単一 RATIONAL タグである GPSAltitude 等は同じ経路では丸められることを実機検証で
            // 確認済み）。回避策として "分子/分母" の分数文字列を CFString として渡すと精度が
            // 保たれるため、ミリメートル精度（分母1000）で書き込む。
            try setTagOrThrow(metadata, name: "GPSAltitude", value: rationalString(abs(ele), denominator: 1000) as CFString, url: request.url)
            try setTagOrThrow(metadata, name: "GPSAltitudeRef", value: (ele >= 0 ? 0 : 1) as CFNumber, url: request.url)
        }

        if let rewrite = request.localRewrite {
            try setTagOrThrow(metadata, name: "OffsetTimeOriginal", value: rewrite.offsetStr as CFString, url: request.url)
            try setTagOrThrow(metadata, name: "OffsetTime", value: rewrite.offsetStr as CFString, url: request.url)
            try setTagOrThrow(metadata, name: "OffsetTimeDigitized", value: rewrite.offsetStr as CFString, url: request.url)
        }
    }

    // MARK: - Stage 2: DateTimeOriginal

    private static func writeStage2DateTime(source stage1URL: URL, destination tempURL: URL, localDto: String) throws {
        guard let source = CGImageSourceCreateWithURL(stage1URL as CFURL, nil) else {
            throw GpsWriteError.cannotOpenSource(stage1URL)
        }
        guard let type = CGImageSourceGetType(source) else {
            throw GpsWriteError.cannotOpenSource(stage1URL)
        }
        guard let destination = CGImageDestinationCreateWithURL(tempURL as CFURL, type, 1, nil) else {
            throw GpsWriteError.writeFailed(stage1URL, "一時ファイルの作成に失敗しました")
        }
        let destOptions: [CFString: Any] = [kCGImageDestinationDateTime: localDto as CFString]
        guard CGImageDestinationCopyImageSource(destination, source, destOptions as CFDictionary, nil) else {
            throw GpsWriteError.writeFailed(stage1URL, "DateTimeOriginal の書き込みに失敗しました")
        }
    }

    // MARK: - 共通ヘルパー

    /// Exif/GPS 名前空間 URI（XMP の exif プレフィックスに対応。CGImageMetadataTagWithPath は
    /// "exif:GPSLatitude" のようなパスを ImageIO 側で Exif/GPS IFD にマップする）。
    /// CFString は Sendable 非準拠だが不変の定数として読み取り専用で使うため nonisolated(unsafe)。
    nonisolated(unsafe) private static let exifNamespaceURI = "http://ns.adobe.com/exif/1.0/" as CFString

    @discardableResult
    private static func setTag(_ metadata: CGMutableImageMetadata, name: String, value: CFTypeRef) -> Bool {
        guard let tag = CGImageMetadataTagCreate(exifNamespaceURI, "exif" as CFString, name as CFString, .default, value) else {
            return false
        }
        let path = "exif:\(name)" as CFString
        return CGImageMetadataSetTagWithPath(metadata, nil, path, tag)
    }

    private static func setTagOrThrow(_ metadata: CGMutableImageMetadata, name: String, value: CFTypeRef, url: URL) throws {
        guard setTag(metadata, name: name, value: value) else {
            throw GpsWriteError.writeFailed(url, "タグ \(name) の設定に失敗しました")
        }
    }

    /// Exif RATIONAL タグ用の "分子/分母" 文字列を生成する
    private static func rationalString(_ value: Double, denominator: Int) -> String {
        let numerator = Int((value * Double(denominator)).rounded())
        return "\(numerator)/\(denominator)"
    }

    private static func tempURL(for url: URL, suffix: String) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString)_\(suffix)_\(url.lastPathComponent)")
    }
}
