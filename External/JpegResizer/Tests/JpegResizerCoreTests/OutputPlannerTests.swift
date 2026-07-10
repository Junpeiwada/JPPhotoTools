import XCTest
import Foundation
@testable import JpegResizerCore

/// 出力計画（命名・上書き判定・連番回避）の純粋ロジック検証。
final class OutputPlannerTests: XCTestCase {

    /// 命名規則は `<stem>-resized.jpg`。拡張子は入力によらず常に `.jpg`。
    func testNamingUsesResizedJpgSuffix() {
        let id = UUID()
        let png = URL(fileURLWithPath: "/in/IMG_0001.png")
        let plans = OutputPlanner.plan(
            targets: [(id, png)],
            allowOverwriteExisting: true, fileExists: { _ in false })
        XCTAssertEqual(plans[0].output.lastPathComponent, "IMG_0001-resized.jpg")
        // 出力先は入力と同じフォルダ。
        XCTAssertEqual(plans[0].output.deletingLastPathComponent().path, "/in")
        XCTAssertFalse(plans[0].willOverwrite)
    }

    /// 別フォルダの同名ファイルを同一出力先へ集約すると、バッチ内衝突は連番で必ず分離される。
    func testPlanDedupesIntraBatchWithSuffix() {
        let id1 = UUID(), id2 = UUID()
        // 同じフォルダに拡張子違いの同名 → 出力名（stem）が衝突する。
        let a = URL(fileURLWithPath: "/in/photo.jpg")
        let b = URL(fileURLWithPath: "/in/photo.png")
        let plans = OutputPlanner.plan(
            targets: [(id1, a), (id2, b)],
            allowOverwriteExisting: true, fileExists: { _ in false })
        XCTAssertEqual(plans.map { $0.output.lastPathComponent },
                       ["photo-resized.jpg", "photo-resized_1.jpg"])
        XCTAssertFalse(plans.contains { $0.willOverwrite })
    }

    /// 既存ファイルは上書き許可ありなら willOverwrite=true として同名を使う。
    func testPlanFlagsExistingAsOverwriteWhenAllowed() {
        let id = UUID()
        let input = URL(fileURLWithPath: "/in/photo.jpg")
        let existing = URL(fileURLWithPath: "/in/photo-resized.jpg").standardizedFileURL
        let plans = OutputPlanner.plan(
            targets: [(id, input)],
            allowOverwriteExisting: true,
            fileExists: { $0.standardizedFileURL == existing })
        XCTAssertEqual(plans[0].output.lastPathComponent, "photo-resized.jpg")
        XCTAssertTrue(plans[0].willOverwrite)
    }

    /// 既存ファイルは上書き不許可なら連番でずらし、既存を温存する（willOverwrite=false）。
    func testPlanAvoidsExistingWhenRenaming() {
        let id = UUID()
        let input = URL(fileURLWithPath: "/in/photo.jpg")
        let existing = URL(fileURLWithPath: "/in/photo-resized.jpg").standardizedFileURL
        let plans = OutputPlanner.plan(
            targets: [(id, input)],
            allowOverwriteExisting: false,
            fileExists: { $0.standardizedFileURL == existing })
        XCTAssertEqual(plans[0].output.lastPathComponent, "photo-resized_1.jpg")
        XCTAssertFalse(plans[0].willOverwrite)
    }
}
