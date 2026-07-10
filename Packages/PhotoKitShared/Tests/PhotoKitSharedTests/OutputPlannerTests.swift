import XCTest
@testable import PhotoKitShared

final class OutputPlannerTests: XCTestCase {
    private let dir = URL(fileURLWithPath: "/tmp/out")

    /// テスト用: 入力 → 同一ディレクトリ、stem+index.jpg。
    private func plan(
        inputs: [String],
        existing: Set<String> = [],
        allowOverwrite: Bool,
        caseInsensitive: Bool
    ) -> [OutputPlan] {
        let targets = inputs.map { (id: UUID(), input: URL(fileURLWithPath: "/in/\($0)")) }
        return OutputPlanner.plan(
            targets: targets,
            directoryFor: { _ in dir },
            fileName: { stem, i in i <= 0 ? "\(stem).jpg" : "\(stem)_\(i).jpg" },
            allowOverwriteExisting: allowOverwrite,
            caseInsensitive: caseInsensitive,
            fileExists: { existing.contains($0.standardizedFileURL.path) }
        )
    }

    /// バッチ内で同名 stem が衝突したら連番でずらす。
    func testBatchCollisionSerialize() {
        let plans = plan(inputs: ["A.png", "A.heic"], allowOverwrite: true, caseInsensitive: false)
        XCTAssertEqual(plans[0].output.lastPathComponent, "A.jpg")
        XCTAssertEqual(plans[1].output.lastPathComponent, "A_1.jpg")
    }

    /// 既存ファイルは allowOverwrite=false なら連番で温存、true なら willOverwrite=true。
    func testExistingRespectsOverwriteFlag() {
        let existing: Set<String> = ["/tmp/out/A.jpg"]
        let keep = plan(inputs: ["A.png"], existing: existing, allowOverwrite: false, caseInsensitive: false)
        XCTAssertEqual(keep[0].output.lastPathComponent, "A_1.jpg")
        XCTAssertFalse(keep[0].willOverwrite)

        let over = plan(inputs: ["A.png"], existing: existing, allowOverwrite: true, caseInsensitive: false)
        XCTAssertEqual(over[0].output.lastPathComponent, "A.jpg")
        XCTAssertTrue(over[0].willOverwrite)
    }

    /// caseInsensitive=true（JpegResizer）: 大小違いの同名は同一出力先とみなして連番回避する。
    /// APFS(case-insensitive) での取り違え・上書き事故を防ぐ（PH1.5 共通化の退行防止）。
    func testCaseInsensitiveBatchCollision() {
        let plans = plan(inputs: ["Photo.png", "photo.png"], allowOverwrite: true, caseInsensitive: true)
        XCTAssertEqual(plans[0].output.lastPathComponent, "Photo.jpg")
        // "photo.jpg" は "Photo.jpg" と大小無視で衝突 → 連番回避
        XCTAssertEqual(plans[1].output.lastPathComponent, "photo_1.jpg")
    }

    /// caseInsensitive=false（GainForge）: 大小違いは別物として扱う（従来挙動）。
    func testCaseSensitiveKeepsBothNames() {
        let plans = plan(inputs: ["Photo.png", "photo.png"], allowOverwrite: true, caseInsensitive: false)
        XCTAssertEqual(plans[0].output.lastPathComponent, "Photo.jpg")
        XCTAssertEqual(plans[1].output.lastPathComponent, "photo.jpg")
    }
}
