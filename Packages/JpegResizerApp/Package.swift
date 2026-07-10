// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "JpegResizerApp",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "JpegResizerApp", targets: ["JpegResizerApp"]),
    ],
    dependencies: [
        // 変換ロジックは External にコピーした JpegResizer パッケージの Core を path 参照。
        .package(path: "../../External/JpegResizer"),
        .package(path: "../PhotoKitShared"),
    ],
    targets: [
        .target(
            name: "JpegResizerApp",
            dependencies: [
                .product(name: "JpegResizerCore", package: "JpegResizer"),
                .product(name: "PhotoKitShared", package: "PhotoKitShared"),
            ]
        ),
    ]
)
