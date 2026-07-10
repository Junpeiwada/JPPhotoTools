// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "JpegResizer",
    platforms: [
        // JPEG リサイズはゲインマップに依存しないため macOS 13 以降で足りる
        // （GainForge の macOS 15 要求は ISO ゲインマップ由来のもの）。
        .macOS(.v13)
    ],
    products: [
        .library(name: "JpegResizerCore", targets: ["JpegResizerCore"]),
        .executable(name: "jpegresizer", targets: ["JpegResizerCLI"]),
    ],
    targets: [
        // 変換ロジックを一元化するコアライブラリ。CLI / GUI から共通利用する（UI 非依存）。
        .target(name: "JpegResizerCore"),
        // CLI は Core を import するだけの薄い実行可能ターゲット。
        .executableTarget(
            name: "JpegResizerCLI",
            dependencies: ["JpegResizerCore"]
        ),
        // リサイズ計画・出力計画の回帰テスト。
        .testTarget(
            name: "JpegResizerCoreTests",
            dependencies: ["JpegResizerCore"]
        ),
    ]
)
