import XCTest
@testable import RawTrashCore

final class RawTrashTests: XCTestCase {
    private var tmp: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent("RawTrashTests-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tmp)
    }

    private func touch(_ name: String) throws {
        try Data().write(to: tmp.appendingPathComponent(name))
    }

    private func exists(_ relativePath: String) -> Bool {
        fm.fileExists(atPath: tmp.appendingPathComponent(relativePath).path)
    }

    /// ペアの揃った RAW は RAW/ へ、孤立 RAW は Del/ へ、JPG は無条件で JPG/ へ。
    func testBasicSorting() throws {
        try touch("A.ARW")     // 孤立 RAW（大文字）
        try touch("B.arw")     // ペアあり
        try touch("B.jpg")
        try touch("C.jpeg")    // JPG 単独
        try touch("note.txt")  // その他 → 残す

        let result = try RawTrash.sort(folderPath: tmp)

        XCTAssertEqual(result, .init(total: 4, deleted: 1, raw: 1, jpg: 2))
        XCTAssertTrue(exists("Del/A.ARW"))
        XCTAssertTrue(exists("RAW/B.arw"))
        XCTAssertTrue(exists("JPG/B.jpg"))
        XCTAssertTrue(exists("JPG/C.jpeg"))
        XCTAssertTrue(exists("note.txt"), "その他ファイルは移動されない")
    }

    /// DNG も RAW として扱う（ペアあり → RAW/、孤立 → Del/、大小は問わない）。
    func testDngIsTreatedAsRaw() throws {
        try touch("P1.dng")     // ペアあり
        try touch("P1.jpg")
        try touch("P2.DNG")     // 孤立 RAW（大文字）

        let result = try RawTrash.sort(folderPath: tmp)

        XCTAssertEqual(result, .init(total: 3, deleted: 1, raw: 1, jpg: 1))
        XCTAssertTrue(exists("RAW/P1.dng"))
        XCTAssertTrue(exists("JPG/P1.jpg"))
        XCTAssertTrue(exists("Del/P2.DNG"))
    }

    /// DNG は他形式からの変換で生まれるため、同名 stem の別 RAW と共存しうる。
    /// 衝突判定は拡張子込みのフルファイル名なので、両方そのままの名前で退避される。
    func testDngCoexistsWithSameStemRaw() throws {
        try touch("DSC0001.dng")
        try touch("DSC0001.arw")  // JPG なし → どちらも孤立

        let result = try RawTrash.sort(folderPath: tmp)

        XCTAssertEqual(result, .init(total: 2, deleted: 2, raw: 0, jpg: 0))
        XCTAssertTrue(exists("Del/DSC0001.dng"))
        XCTAssertTrue(exists("Del/DSC0001.arw"), "拡張子が違うため連番退避されない")
    }

    /// ペア判定は大小無視の stem 一致（DSC.ARW と dsc.jpg はペア）。
    func testCaseInsensitivePairing() throws {
        try touch("DSC0001.ARW")
        try touch("dsc0001.jpg")

        let result = try RawTrash.sort(folderPath: tmp)

        XCTAssertEqual(result.deleted, 0, "大小無視でペアと判定され Del には行かない")
        XCTAssertTrue(exists("RAW/DSC0001.ARW"))
    }

    /// 宛先に同名がある場合は連番退避（上書きしない）。
    func testCollisionRenamesInsteadOfOverwrite() throws {
        try fm.createDirectory(at: tmp.appendingPathComponent("Del"), withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: tmp.appendingPathComponent("Del/orphan.arw"))
        try touch("orphan.arw") // 孤立 RAW（同名が Del に既存）

        _ = try RawTrash.sort(folderPath: tmp)

        XCTAssertTrue(exists("Del/orphan.arw"), "既存ファイルは残る")
        XCTAssertTrue(exists("Del/orphan_1.arw"), "新規は連番で退避される")
        let kept = try String(contentsOf: tmp.appendingPathComponent("Del/orphan.arw"), encoding: .utf8)
        XCTAssertEqual(kept, "existing", "既存ファイルは上書きされない")
    }

    /// パス2側（RAW/ への移動）でも連番退避が効く。
    func testPairedRawCollisionInRawDir() throws {
        try fm.createDirectory(at: tmp.appendingPathComponent("RAW"), withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: tmp.appendingPathComponent("RAW/B.arw"))
        try touch("B.arw")   // ペアあり → RAW/ へ（同名が既存）
        try touch("B.jpg")

        _ = try RawTrash.sort(folderPath: tmp)

        XCTAssertTrue(exists("RAW/B.arw"), "既存は残る")
        XCTAssertTrue(exists("RAW/B_1.arw"), "新規は連番で退避")
    }

    /// 空フォルダは何も移動せず total 0 を返す（出力フォルダ作成でエラーにならない）。
    func testEmptyFolder() throws {
        let result = try RawTrash.sort(folderPath: tmp)
        XCTAssertEqual(result, .init(total: 0, deleted: 0, raw: 0, jpg: 0))
    }

    func testMissingFolderThrows() throws {
        let missing = tmp.appendingPathComponent("does-not-exist")
        XCTAssertThrowsError(try RawTrash.sort(folderPath: missing)) { error in
            XCTAssertEqual(error as? RawTrash.SortError, .folderNotFound(missing))
        }
    }
}
