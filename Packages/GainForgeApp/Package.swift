// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "GainForgeApp",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "GainForgeApp", targets: ["GainForgeApp"]),
    ],
    dependencies: [
        .package(path: "../../External/GainForge"),
        .package(path: "../PhotoKitShared"),
    ],
    targets: [
        .target(
            name: "GainForgeApp",
            dependencies: [
                .product(name: "GainForgeCore", package: "GainForge"),
                .product(name: "PhotoKitShared", package: "PhotoKitShared"),
            ]
        ),
    ]
)
