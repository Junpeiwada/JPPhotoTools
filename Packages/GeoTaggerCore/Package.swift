// swift-tools-version:6.0
import PackageDescription

// GPX トラックログで JPEG にジオタグを付与するロジック層（UI 非依存）。
// 座標→タイムゾーン変換は SwiftTimeZoneLookup（BSD-3-Clause、オフライン、~5.6MB の
// 境界データ同梱、~20m 解像度）を使用する。
let package = Package(
    name: "GeoTaggerCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "GeoTaggerCore", targets: ["GeoTaggerCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/patrick-zippenfenig/SwiftTimeZoneLookup.git", from: "1.0.8"),
    ],
    targets: [
        .target(
            name: "GeoTaggerCore",
            dependencies: [
                .product(name: "SwiftTimeZoneLookup", package: "SwiftTimeZoneLookup"),
            ]
        ),
        .testTarget(name: "GeoTaggerCoreTests", dependencies: ["GeoTaggerCore"]),
    ]
)
