import Foundation
import AppKit
import SwiftUI

/// 変換系タブの共通シェル。ドロップ受け入れ・probe スロットル・スライディングウィンドウ並列変換・
/// 上書き確認・集計という骨格を、機能定義 `FeatureShell` 経由で汎用化する。
///
/// 設計:
/// - 機能固有の設定（品質・リサイズ・SDR 方式など）は**サブクラス**が `@Published` で保持し、
///   `makeSettings()` で `F.Settings` に束ねてこのシェルへ渡す（永続化・UI 束縛はサブクラス責務）。
/// - このシェル自体は `open class` で、GainForge / JpegResizer の ViewModel が継承して使う。
/// - 変換の中身・probe 内容・出力計画は `feature`（`FeatureShell`）に委譲するため、ここには
///   変換ロジックを一切持たない（設計原則の維持）。
@MainActor
open class AppViewModel<F: FeatureShell>: ObservableObject {
    public typealias Item = FileItem<F.Extra>

    /// 機能定義。probe・変換・出力計画をここへ委譲する。
    public let feature: F

    // MARK: - 一覧
    @Published public private(set) var items: [Item] = []
    /// 一覧テーブルの選択行。
    @Published public var selection: Set<Item.ID> = []

    // MARK: - 実行状態
    @Published public private(set) var isConverting = false
    private var cancelRequested = false
    /// 処理中に計画外の既存ファイルへ衝突し、安全のためバッチを止めたか（完了後の通知に使う）。
    private var haltedByUnexpected = false

    // MARK: - probe スロットル
    private var probeQueue: [Item.ID] = []
    private var activeProbes = 0
    private let maxProbeConcurrency = max(2, min(ProcessInfo.processInfo.activeProcessorCount, 4))

    public init(feature: F) {
        self.feature = feature
    }

    // MARK: - サブクラスが実装する注入点

    /// 現在の設定を `F.Settings` に束ねて返す（バッチ開始・probe 時にスナップショットされる）。
    open func makeSettings() -> F.Settings {
        fatalError("makeSettings() must be overridden")
    }

    /// バッチ開始前（出力計画・上書き確認の後、実変換の前）に一度だけ呼ばれる注入点。
    /// `extras` は今回実際に変換する行の機能固有情報。サブクラスが機能固有の開始前通知
    /// （GainForge の ML/LUT 降格通知など、`@MainActor` 状態を伴う判定）に使う。既定は何もしない。
    /// 上書き確認でキャンセルした場合は呼ばれない（`startConversion` が早期 return するため）。
    open func willStartConversion(extras: [F.Extra]) {}

    // MARK: - 派生状態

    public var phase: AppPhase {
        if isConverting { return .converting }
        if items.isEmpty { return .empty }
        if items.contains(where: { $0.status == .waiting }) { return .ready }
        return .finished
    }

    /// 今回の変換で処理する対象行の ID 群。選択があれば選択の「変換中以外」を、なければ既定対象を全件。
    public var conversionTargetIDs: [Item.ID] {
        let selectedConvertible = items.filter {
            selection.contains($0.id) && Self.isReconvertible($0.status)
        }
        if !selectedConvertible.isEmpty { return selectedConvertible.map { $0.id } }
        return items.filter { Self.isDefaultConvertTarget($0.status) }.map { $0.id }
    }

    public var conversionTargetCount: Int { conversionTargetIDs.count }

    public var hasConvertibleSelection: Bool {
        items.contains { Self.isReconvertible($0.status) && selection.contains($0.id) }
    }

    /// 選択して再変換できる状態か。変換中以外はすべて対象（既存行も選べばやり直せる）。
    public static func isReconvertible(_ status: RowStatus) -> Bool {
        status != .converting
    }

    /// 選択なしの「すべて変換」で既定の対象とみなす状態か。待機・完了・エラー・スキップを含む。
    /// 既存（変換前から在った出力）はこちらが作ったとは限らないため既定では外し、変換中は対象外。
    public static func isDefaultConvertTarget(_ status: RowStatus) -> Bool {
        switch status {
        case .waiting, .done, .error, .skipped: return true
        case .existing, .converting: return false
        }
    }

    public var canConvert: Bool { isConverting || conversionTargetCount > 0 }
    public var canClear: Bool { !items.isEmpty && !isConverting }
    public var canEditSettings: Bool { !isConverting }

    // MARK: - 集計（ステータスバー用）

    public var totalCount: Int { items.count }
    public var completedCount: Int {
        items.filter { $0.status == .done || $0.status == .error || $0.status == .skipped }.count
    }
    public var errorCount: Int { items.filter { $0.status == .error }.count }
    public var skippedCount: Int { items.filter { $0.status == .skipped }.count }

    public var sizeTotals: (input: Int, output: Int) {
        items.filter { $0.status == .done }.reduce(into: (0, 0)) { acc, item in
            acc.0 += item.inputBytes ?? 0
            acc.1 += item.outputBytes ?? 0
        }
    }

    // MARK: - ドロップ受け入れ

    /// ドロップされた URL 群（ファイル / フォルダ）を一覧に追加する。収集はバックグラウンド。
    public func addDropped(_ urls: [URL]) {
        let feature = self.feature
        Task {
            let images = await Task.detached(priority: .utility) {
                feature.collectInputs(urls).map { $0.standardizedFileURL }
            }.value
            mergeNewItems(images)
        }
    }

    /// 収集済み入力 URL を重複排除して一覧へ追加する（同期・MainActor）。戻り値は追加件数。
    @discardableResult
    public func mergeNewItems(_ images: [URL]) -> Int {
        var seen = Set(items.map { $0.inputURL.standardizedFileURL })
        var added: [Item] = []
        for url in images {
            let std = url.standardizedFileURL
            guard seen.insert(std).inserted else { continue }
            added.append(FileItem(inputURL: std, extra: feature.initialExtra))
        }
        guard !added.isEmpty else { return 0 }
        items.append(contentsOf: added)
        for item in added { enqueueProbe(item.id) }
        return added.count
    }

    private func enqueueProbe(_ id: Item.ID) {
        probeQueue.append(id)
        pumpProbes()
    }

    /// 同時実行数の上限まで probe を起動する。1 件完了ごとに補充する。
    private func pumpProbes() {
        while activeProbes < maxProbeConcurrency, !probeQueue.isEmpty {
            let id = probeQueue.removeFirst()
            guard let url = items.first(where: { $0.id == id })?.inputURL else { continue }
            activeProbes += 1
            // 既存出力の検出先は設定に依存し得るため、起動時点の設定をスナップショットして渡す。
            let settings = makeSettings()
            let feature = self.feature
            Task.detached(priority: .utility) { [weak self] in
                let result = feature.probe(url, settings: settings)
                await self?.finishProbe(id: id, result: result)
            }
        }
    }

    private func finishProbe(id: Item.ID, result: ProbeResult<F.Extra>) {
        activeProbes -= 1
        applyProbe(id: id, result: result)
        pumpProbes()
    }

    /// probe 結果を行へ反映する。変換が先に走って確定済みの値は上書きしない。
    private func applyProbe(id: Item.ID, result: ProbeResult<F.Extra>) {
        update(id) { item in
            if item.inputBytes == nil { item.inputBytes = result.inputBytes }
            // 機能固有情報（extra）の反映は待機中の行に限る。probe がスロットルで遅れ、変換が
            // 先に確定した行（変換中/完了/既存）に着弾しても、確定済みの extra（出力寸法など）を
            // 潰さない（移行前の「確定済みは上書きしない」不変条件）。
            if item.status == .waiting { item.extra = result.extra }
            if let png = result.thumbnailPNG, item.thumbnail == nil {
                item.thumbnail = NSImage(data: png)
            }
            // 変換前から対応出力があれば「既存」にし、変換せず扱えるようにする（GainForge のみ）。
            // 変換が先に走って確定済みの行は触らない。
            if item.status == .waiting, let existing = result.existingOutput {
                item.status = .existing
                item.outputURL = existing.url
                item.outputBytes = existing.bytes
            }
        }
    }

    // MARK: - 行操作

    public func remove(ids: Set<Item.ID>) {
        guard !isConverting else { return }
        items.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
    }

    public func clear() {
        guard canClear else { return }
        items.removeAll()
        selection.removeAll()
    }

    /// 行を更新する小ヘルパ。
    public func update(_ id: Item.ID, _ mutate: (inout Item) -> Void) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[idx])
    }

    // MARK: - バッチ変換

    open func convertOrCancel() {
        if isConverting {
            cancelRequested = true
        } else {
            startConversion()
        }
    }

    private func startConversion() {
        let targetIDs = conversionTargetIDs
        guard !targetIDs.isEmpty else { return }

        let settings = makeSettings()
        let targets: [(id: UUID, input: URL)] = targetIDs.compactMap { id in
            guard let input = items.first(where: { $0.id == id })?.inputURL else { return nil }
            return (id, input)
        }
        let exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
        let dirFor: (URL) -> URL = { [feature] in feature.outputDirectory(for: $0, settings: settings) }
        let nameFor: (String, Int) -> String = { [feature] in feature.outputFileName(stem: $0, index: $1, settings: settings) }

        let caseInsensitive = feature.outputIsCaseInsensitive
        var plans = OutputPlanner.plan(targets: targets, directoryFor: dirFor, fileName: nameFor,
                                       allowOverwriteExisting: true,
                                       caseInsensitive: caseInsensitive, fileExists: exists)

        // 既存ファイルを上書きする行があれば、開始前に確認する。
        let overwriting = plans.filter { $0.willOverwrite }
        if !overwriting.isEmpty {
            switch presentOverwriteConfirmation(overwriting) {
            case .cancel:
                return
            case .overwrite:
                break
            case .rename:
                plans = OutputPlanner.plan(targets: targets, directoryFor: dirFor, fileName: nameFor,
                                           allowOverwriteExisting: false,
                                           caseInsensitive: caseInsensitive, fileExists: exists)
            }
        }

        let planByID = Dictionary(uniqueKeysWithValues:
            plans.map { ($0.id, (output: $0.output, overwrite: $0.willOverwrite)) })
        let orderedIDs = plans.map { $0.id }

        // 機能固有の開始前通知（GainForge の ML 降格など）。出力計画・上書き確認が済み、実際に変換する
        // 行が orderedIDs で確定した後に一度だけ呼ぶ。サブクラス（状態を持てる ViewModel）が
        // willStartConversion を override して使う（feature は struct で didNotify 等の状態を持てない）。
        let convertingExtras = orderedIDs.compactMap { id in items.first(where: { $0.id == id })?.extra }
        willStartConversion(extras: convertingExtras)

        isConverting = true
        cancelRequested = false
        haltedByUnexpected = false

        let maxConcurrent = max(1, min(ProcessInfo.processInfo.activeProcessorCount, 3))

        Task {
            let waitingIDs = orderedIDs
            var next = 0

            await withTaskGroup(of: Void.self) { group in
                var inFlight = 0
                while inFlight < maxConcurrent, next < waitingIDs.count, !cancelRequested {
                    if let op = conversionOperation(for: waitingIDs[next], plan: planByID[waitingIDs[next]],
                                                    settings: settings) {
                        group.addTask(priority: .userInitiated, operation: op)
                        inFlight += 1
                    }
                    next += 1
                }
                while await group.next() != nil {
                    inFlight -= 1
                    while next < waitingIDs.count, !cancelRequested {
                        let id = waitingIDs[next]
                        next += 1
                        if let op = conversionOperation(for: id, plan: planByID[id], settings: settings) {
                            group.addTask(priority: .userInitiated, operation: op)
                            inFlight += 1
                            break
                        }
                    }
                }
            }

            isConverting = false
            cancelRequested = false
            if haltedByUnexpected {
                haltedByUnexpected = false
                presentHaltedNotice()
            }
        }
    }

    /// 1 行分の変換オペレーションを生成する（行が無ければ nil）。呼び出し時に当該行を「変換中」にする。
    private func conversionOperation(
        for id: Item.ID,
        plan: (output: URL, overwrite: Bool)?,
        settings: F.Settings
    ) -> (@Sendable () async -> Void)? {
        guard let plan, let input = items.first(where: { $0.id == id })?.inputURL else { return nil }

        update(id) { $0.status = .converting }

        let output = plan.output
        let overwrite = plan.overwrite
        let dir = output.deletingLastPathComponent()
        let feature = self.feature

        return { [weak self] in
            let outcome: ConversionOutcome = await Task.detached(priority: .userInitiated) {
                do {
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let r = try feature.convert(input: input, output: output, overwrite: overwrite, settings: settings)
                    return .success(r)
                } catch let e as FeatureConversionError {
                    switch e {
                    case .blocked(let m): return .blocked(m)
                    case .failed(let m):  return .failure(m)
                    }
                } catch {
                    return .failure(error.localizedDescription)
                }
            }.value
            await self?.applyOutcome(id: id, outcome: outcome)
        }
    }

    /// 変換タスクの結果（Task 境界を越えるため Sendable）。
    private enum ConversionOutcome: Sendable {
        case success(ConversionSuccess<F.Extra>)
        case failure(String)
        case blocked(String)
    }

    private func applyOutcome(id: Item.ID, outcome: ConversionOutcome) {
        switch outcome {
        case .success(let r):
            update(id) { item in
                item.status = .done
                item.outputURL = r.outputURL
                item.outputBytes = r.outputBytes
                if item.inputBytes == nil { item.inputBytes = r.inputBytes }
                // 機能固有の付加情報（出力寸法など）があれば反映する。
                if let extra = r.resultExtra { item.extra = extra }
            }
        case .failure(let message):
            update(id) { item in
                item.status = .error
                item.errorMessage = message
            }
        case .blocked(let message):
            update(id) { item in
                item.status = .error
                item.errorMessage = message
            }
            haltedByUnexpected = true
            cancelRequested = true
        }
    }

    // MARK: - 確認ダイアログ（AppKit）

    private func presentOverwriteConfirmation(_ overwriting: [OutputPlan]) -> OverwriteResolution {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "出力先に既存ファイルがあります（\(overwriting.count) 件）"
        alert.informativeText = Self.overwriteList(overwriting)
            + "\n\n「上書き」既存を置き換えます／「別名で保存」既存を残し連番で保存します。"
        alert.addButton(withTitle: "上書き")
        alert.addButton(withTitle: "別名で保存")
        alert.addButton(withTitle: "キャンセル")
        switch alert.runModal() {
        case .alertFirstButtonReturn:  return .overwrite
        case .alertSecondButtonReturn: return .rename
        default:                       return .cancel
        }
    }

    private func presentHaltedNotice() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "予期せぬ既存ファイルのため変換を中断しました"
        alert.informativeText = "変換中に、計画になかった同名ファイルが出力先に現れたため、"
            + "安全のため残りの変換を停止しました。状況を確認のうえ、もう一度変換してください。"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func overwriteList(_ plans: [OutputPlan], limit: Int = 10) -> String {
        var text = plans.prefix(limit).map { "・\($0.output.lastPathComponent)" }.joined(separator: "\n")
        if plans.count > limit { text += "\n・ほか \(plans.count - limit) 件" }
        return text
    }
}
