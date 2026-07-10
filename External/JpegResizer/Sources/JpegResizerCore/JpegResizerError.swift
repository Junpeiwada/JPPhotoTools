import Foundation

/// JpegResizer の変換処理で発生し得るエラー。GUI でのメッセージ表示のため型付きにする。
public enum JpegResizerError: Error, Sendable {
    /// 入力画像ソースを開けなかった。
    case cannotReadSource(URL)
    /// 入力画像をデコード／再サンプルできなかった。
    case imageUnreadable(URL)
    /// JPEG 出力先を生成できなかった（親ディレクトリ不在など）。
    case destinationCreateFailed(URL)
    /// JPEG のファイナライズ（書き出し確定）に失敗した。
    case finalizeFailed(URL)
    /// 出力先に既存ファイルがあり、上書き許可なしで変換しようとした。
    case outputExists(URL)
}

extension JpegResizerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .cannotReadSource(let url):
            return "入力画像を読み込めませんでした: \(url.lastPathComponent)"
        case .imageUnreadable(let url):
            return "画像をデコードできませんでした: \(url.lastPathComponent)"
        case .destinationCreateFailed(let url):
            return "出力先を作成できませんでした: \(url.lastPathComponent)"
        case .finalizeFailed(let url):
            return "JPEG の書き出しに失敗しました: \(url.lastPathComponent)"
        case .outputExists(let url):
            return "出力先に既存ファイルがあります: \(url.lastPathComponent)"
        }
    }
}
