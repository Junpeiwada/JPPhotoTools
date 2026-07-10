// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PhotoKitShared",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "PhotoKitShared", targets: ["PhotoKitShared"]),
    ],
    targets: [
        // 変換系タブ（GainForge / JpegResizer）で重複していた App シェルの共通部品を集約する。
        // UI 非依存の純粋ロジックと、機能に依存しない SwiftUI 部品のみを置く（機能固有ロジックは
        // 各機能モジュールに残す）。
        .target(name: "PhotoKitShared"),
    ]
)
