import Foundation

public enum GpsWriteError: Error, Sendable {
    case exiftoolNotFound
    case writeFailed(URL, String)
}

/// exiftool プロセス起動による GPS / 日時タグの書き込み。
///
/// 経緯: 当初 ImageIO（CGImageDestinationCopyImageSource）で無劣化書き込みを試みたが、
/// Sony 機の HDR 撮影による MPF 形式 Gain Map（JPEG 内の補助画像）が ImageIO 側の制約で
/// 壊れる（`MPImageType` が `Undefined` 化）ことが実写真での検証で判明し、回避策も
/// 見つからなかった。そのため元 GeoTagger と同じ exiftool 方式（`-overwrite_original` で
/// 無劣化上書き）に戻した。
public enum GpsWriter {
    /// Homebrew の一般的なインストール先を優先的に探す。パッケージ済みアプリはシェルの
    /// PATH を継承しないため、既知パスの直接チェックが必要（元 GeoTagger の main.ts と同じ方式）。
    public static func detectExiftool() -> String? {
        let candidates = ["/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool", "/usr/bin/exiftool"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    /// 書き込むタグ（元 GeoTagger と同一）:
    /// - GPSLatitude + GPSLatitudeRef(N/S) / GPSLongitude + GPSLongitudeRef(E/W)
    /// - ele がある場合のみ GPSAltitude + GPSAltitudeRef(0/1)
    /// - localRewrite がある場合のみ DateTimeOriginal / OffsetTimeOriginal /
    ///   OffsetTime / OffsetTimeDigitized
    public static func write(_ request: GpsWriteRequest) throws {
        guard let exiftoolPath = detectExiftool() else {
            throw GpsWriteError.exiftoolNotFound
        }

        var args: [String] = [
            "-GPSLatitude=\(abs(request.lat))",
            "-GPSLatitudeRef=\(request.lat >= 0 ? "N" : "S")",
            "-GPSLongitude=\(abs(request.lon))",
            "-GPSLongitudeRef=\(request.lon >= 0 ? "E" : "W")",
        ]
        if let ele = request.ele {
            args += ["-GPSAltitude=\(abs(ele))", "-GPSAltitudeRef=\(ele >= 0 ? "0" : "1")"]
        }
        if let rewrite = request.localRewrite {
            args += [
                "-DateTimeOriginal=\(rewrite.localDto)",
                "-OffsetTimeOriginal=\(rewrite.offsetStr)",
                "-OffsetTime=\(rewrite.offsetStr)",
                "-OffsetTimeDigitized=\(rewrite.offsetStr)",
            ]
        }
        args += ["-overwrite_original", request.url.path]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: exiftoolPath)
        process.arguments = args
        let stderrPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw GpsWriteError.writeFailed(request.url, error.localizedDescription)
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GpsWriteError.writeFailed(request.url, (message?.isEmpty == false ? message! : "exit code \(process.terminationStatus)"))
        }
    }
}
