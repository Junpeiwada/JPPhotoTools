import PhotoKitShared

/// 一覧の 1 行 = 1 入力ファイル。共通コア（PhotoKitShared.FileItem）に
/// JpegResizer 固有の付加情報（`JpegResizerExtra`: 元寸法・出力寸法）を組み合わせたもの。
/// View 側の `FileItem` 参照をなるべく変えずに済ませるための typealias。
typealias FileItem = PhotoKitShared.FileItem<JpegResizerExtra>
