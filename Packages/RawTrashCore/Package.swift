// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "RawTrashCore",
    platforms: [
        // 統合アプリ（JPPhotoTools）に合わせる。純ファイル操作なので下限は本来もっと低いが、
        // GainForge の ISO ゲインマップ要求に合わせた統合アプリの最低要件へ揃える。
        .macOS(.v15)
    ],
    products: [
        .library(name: "RawTrashCore", targets: ["RawTrashCore"]),
    ],
    targets: [
        // RAW/JPG ペア仕分けロジック。UI 非依存・FileManager のみで完結（外部依存なし）。
        // 元 Electron 実装（RAW-Trash の src/main/sorter.ts）を 1:1 で Swift へ移植したもの。
        .target(name: "RawTrashCore"),
        .testTarget(
            name: "RawTrashCoreTests",
            dependencies: ["RawTrashCore"]
        ),
    ]
)
