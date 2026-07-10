import XCTest
import Foundation
import JpegResizerCore
@testable import JpegResizer

@MainActor
final class AppViewModelTests: XCTestCase {

    var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("JpegResizerAppTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    /// テスト専用 suite を注入した ViewModel を作る。
    private func makeVM(suiteName: String? = nil) -> AppViewModel {
        let name = suiteName ?? "jr.test.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return AppViewModel(defaults: suite)
    }

    private func touchJPEG(_ name: String) throws -> URL {
        let url = tmp.appendingPathComponent(name)
        try Data().write(to: url)
        return url
    }

    // MARK: - 初期状態

    func testInitialState() {
        let vm = makeVM()
        XCTAssertEqual(vm.phase, .empty)
        XCTAssertFalse(vm.canConvert)
        XCTAssertFalse(vm.canClear)
        XCTAssertTrue(vm.canEditSettings)
        XCTAssertEqual(vm.totalCount, 0)
    }

    // MARK: - 追加・重複排除・派生状態

    func testMergeAddsAndDerivesReadyPhase() throws {
        let vm = makeVM()
        let a = try touchJPEG("a.jpg")
        let b = try touchJPEG("b.jpg")
        let n = vm.mergeNewItems([a, b])
        XCTAssertEqual(n, 2)
        XCTAssertEqual(vm.totalCount, 2)
        XCTAssertEqual(vm.phase, .ready)
        XCTAssertTrue(vm.canConvert)
        XCTAssertTrue(vm.canClear)
    }

    func testMergeDedupsExistingAndWithinBatch() throws {
        let vm = makeVM()
        let a = try touchJPEG("a.jpg")
        XCTAssertEqual(vm.mergeNewItems([a]), 1)
        XCTAssertEqual(vm.mergeNewItems([a]), 0)
        let b = try touchJPEG("b.jpg")
        XCTAssertEqual(vm.mergeNewItems([b, b]), 1)
        XCTAssertEqual(vm.totalCount, 2)
    }

    func testClearResetsToEmpty() throws {
        let vm = makeVM()
        _ = vm.mergeNewItems([try touchJPEG("a.jpg")])
        vm.clear()
        XCTAssertEqual(vm.phase, .empty)
        XCTAssertEqual(vm.totalCount, 0)
    }

    func testRemoveByIDs() throws {
        let vm = makeVM()
        _ = vm.mergeNewItems([try touchJPEG("a.jpg"), try touchJPEG("b.jpg")])
        let firstID = vm.items.first!.id
        vm.remove(ids: [firstID])
        XCTAssertEqual(vm.totalCount, 1)
        XCTAssertFalse(vm.items.contains { $0.id == firstID })
    }

    // MARK: - 永続化

    func testSettingsPersistAcrossInstances() {
        let suite = "jr.test.persist.\(UUID().uuidString)"
        let vm1 = makeVM(suiteName: suite)
        vm1.quality = 0.7
        vm1.resizeKind = .width
        vm1.resizeWidth = 2560
        vm1.resizeMegapixels = 12
        vm1.resizeHeight = 1440

        let vm2 = AppViewModel(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(vm2.quality, 0.7, accuracy: 0.0001)
        XCTAssertEqual(vm2.resizeKind, .width)
        XCTAssertEqual(vm2.resizeWidth, 2560)
        XCTAssertEqual(vm2.resizeMegapixels, 12, accuracy: 0.0001)
        XCTAssertEqual(vm2.resizeHeight, 1440)
    }

    /// `resizeKind` と各数値から Core の `ResizeMode` を正しく組み立てること。
    func testResizeModeConstruction() {
        let vm = makeVM()
        vm.resizeMegapixels = 8
        vm.resizeWidth = 3840
        vm.resizeHeight = 2160

        vm.resizeKind = .original
        XCTAssertEqual(vm.resizeMode, .original)
        vm.resizeKind = .megapixels
        XCTAssertEqual(vm.resizeMode, .megapixels(8))
        vm.resizeKind = .width
        XCTAssertEqual(vm.resizeMode, .fitWidth(3840))
        vm.resizeKind = .height
        XCTAssertEqual(vm.resizeMode, .fitHeight(2160))
    }

    /// 現在のリサイズ設定で元寸法→出力寸法の予測が正しいこと。
    func testPlannedOutputSize() {
        let vm = makeVM()
        vm.resizeKind = .width
        vm.resizeWidth = 2000
        XCTAssertEqual(vm.plannedOutputSize(for: CGSize(width: 4000, height: 3000)),
                       CGSize(width: 2000, height: 1500))
        // 縮小にならない場合は原寸のまま。
        vm.resizeKind = .original
        XCTAssertEqual(vm.plannedOutputSize(for: CGSize(width: 4000, height: 3000)),
                       CGSize(width: 4000, height: 3000))
    }

    func testResetSettingsRestoresDefaultsAndPersists() {
        let suite = "jr.test.reset.\(UUID().uuidString)"
        let vm = makeVM(suiteName: suite)
        vm.quality = 0.95
        vm.resizeKind = .megapixels
        vm.resizeMegapixels = 24

        vm.resetSettings()
        XCTAssertEqual(vm.quality, AppViewModel.Defaults.quality, accuracy: 0.0001)
        XCTAssertEqual(vm.resizeKind, AppViewModel.Defaults.resizeKind)
        XCTAssertEqual(vm.resizeMegapixels, AppViewModel.Defaults.resizeMegapixels, accuracy: 0.0001)

        let vm2 = AppViewModel(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(vm2.quality, AppViewModel.Defaults.quality, accuracy: 0.0001)
        XCTAssertEqual(vm2.resizeKind, AppViewModel.Defaults.resizeKind)
    }

    // MARK: - 純粋ヘルパ

    func testReductionLabel() {
        XCTAssertEqual(SizeFormat.reductionLabel(input: 100, output: 28), "-72%")
        XCTAssertEqual(SizeFormat.reductionLabel(input: 100, output: 100), "±0%")
        XCTAssertEqual(SizeFormat.reductionLabel(input: 100, output: 120), "+20%")
        XCTAssertEqual(SizeFormat.reductionLabel(input: 0, output: 0), "")
    }

    func testBeforeAfterLabel() {
        XCTAssertEqual(SizeFormat.beforeAfter(input: nil, output: nil, status: .waiting), "- → -")
        XCTAssertEqual(SizeFormat.beforeAfter(input: 1_048_576, output: nil, status: .converting), "1.0MB → …")
        XCTAssertEqual(SizeFormat.beforeAfter(input: 2_097_152, output: 1_048_576, status: .done), "2.0MB → 1.0MB")
    }

    func testDimensionFormat() {
        XCTAssertEqual(SizeFormat.dimension(CGSize(width: 3000, height: 4000)), "3000×4000")
        XCTAssertEqual(SizeFormat.dimension(nil), "-")
        XCTAssertEqual(SizeFormat.dimensionBeforeAfter(
            original: CGSize(width: 6000, height: 4000),
            output: CGSize(width: 3840, height: 2560)), "6000×4000 → 3840×2560")
    }

    // MARK: - 変換対象の判定

    /// 再変換対象の判定表。完了・エラー・スキップ行も選択すれば再変換でき、選択なしの
    /// 「すべて変換」にも含まれる。変換中は常に対象外。
    func testConvertTargetDecisionTable() {
        XCTAssertTrue(AppViewModel.isReconvertible(.waiting))
        XCTAssertTrue(AppViewModel.isReconvertible(.done))
        XCTAssertTrue(AppViewModel.isReconvertible(.error))
        XCTAssertTrue(AppViewModel.isReconvertible(.skipped))
        XCTAssertFalse(AppViewModel.isReconvertible(.converting))

        XCTAssertTrue(AppViewModel.isDefaultConvertTarget(.waiting))
        XCTAssertTrue(AppViewModel.isDefaultConvertTarget(.done))
        XCTAssertTrue(AppViewModel.isDefaultConvertTarget(.error))
        XCTAssertTrue(AppViewModel.isDefaultConvertTarget(.skipped))
        XCTAssertFalse(AppViewModel.isDefaultConvertTarget(.converting))
    }

    /// 選択があればそれが変換対象、無ければ全件（既定対象）。
    func testConversionTargetsSelectionPriority() throws {
        let vm = makeVM()
        _ = vm.mergeNewItems([try touchJPEG("a.jpg"), try touchJPEG("b.jpg")])
        // 選択なし → 全件が対象。
        XCTAssertEqual(vm.conversionTargetCount, 2)
        XCTAssertFalse(vm.hasConvertibleSelection)
        // 選択あり → 選択のみ。
        let firstID = vm.items.first!.id
        vm.selection = [firstID]
        XCTAssertEqual(vm.conversionTargetIDs, [firstID])
        XCTAssertTrue(vm.hasConvertibleSelection)
    }
}
