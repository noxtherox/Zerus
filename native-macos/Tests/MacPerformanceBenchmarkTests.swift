import XCTest
@testable import Zerus_Native

/// Opt-in timings against a real vault. Set `TEST_RUNNER_ZERUS_BENCH_VAULT`
/// (and optionally `TEST_RUNNER_ZERUS_BENCH_BOARD`, default `Work/Epics`) when
/// running `xcodebuild test`. The board benchmark moves one card to another
/// column and back, so only point it at a vault that is safe to edit.
@MainActor
final class MacPerformanceBenchmarkTests: XCTestCase {
    private var vault: URL? { ProcessInfo.processInfo.environment["ZERUS_BENCH_VAULT"].map { URL(fileURLWithPath: $0) } }
    private var board: String { ProcessInfo.processInfo.environment["ZERUS_BENCH_BOARD"] ?? "Work/Epics" }

    private func time<T>(_ label: String, runs: Int = 1, _ work: () async throws -> T) async rethrows -> T {
        var result: T?
        var samples: [Double] = []
        for _ in 0..<runs {
            let start = ContinuousClock.now
            result = try await work()
            let elapsed = start.duration(to: .now)
            samples.append(Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)
        }
        let sorted = samples.sorted()
        print(String(format: "ZBENCH %@ median=%.1fms min=%.1fms max=%.1fms runs=%d", label, sorted[sorted.count / 2], sorted.first!, sorted.last!, runs))
        return result!
    }

    func testProfileLoop() async throws {
        guard let vault, let label = ProcessInfo.processInfo.environment["ZERUS_BENCH_PROFILE"] else { throw XCTSkip("profile only") }
        let store = MacWorkspace(); await store.openVault(vault)
        let io = try XCTUnwrap(store.io)
        for _ in 0..<40 {
            switch label {
            case "bulk": _ = try await io.bulkSnapshot()
            case "scan": _ = try await io.scan()
            default: _ = try await io.imageSnapshot()
            }
        }
    }
    func testVaultTimings() async throws {
        guard let vault else { throw XCTSkip("Set TEST_RUNNER_ZERUS_BENCH_VAULT to run benchmarks.") }
        let store = MacWorkspace()
        await time("openVault") { await store.openVault(vault) }
        let io = try XCTUnwrap(store.io)
        _ = try await time("scan", runs: 3) { try await io.scan() }
        _ = try await time("bulkSnapshot", runs: 3) { try await io.bulkSnapshot() }
        _ = try await time("imageSnapshot", runs: 3) { try await io.imageSnapshot() }
        await time("refresh(poll)", runs: 3) { await store.refresh() }
        await time("openCollection") { await store.openCollection(board, folder: true) }
        if store.viewMode != "Kanban" { await store.updateCollectionLayout(store.collectionLayout, mode: "Kanban") }
        _ = await time("boardSnapshot", runs: 10) { store.boardSnapshot }
        _ = await time("collectionFields(uncached)", runs: 5) { store.notes = store.notes; return store.collectionFields }

        let scope = try XCTUnwrap(store.boardScope, "The benchmark board needs a grouping property")
        let groups = try XCTUnwrap(store.boardSnapshot).groups
        let source = try XCTUnwrap(groups.first { !$0.notes.isEmpty })
        let target = try XCTUnwrap(groups.first { $0.value != source.value && $0.value != nil }?.value)
        let note = try XCTUnwrap(source.notes.first)
        let transfer = MacBoardTransfer(scope: scope, item: .notes([note.path]))
        try await time("boardDrop(total)") {
            let plan = try await time("boardDrop.prepare") { try await store.prepareBoardDrop(transfer, target: target, scope: scope) }
            try await time("boardDrop.commit") { try await store.commitBoardDrop(plan, scope: scope) }
        }
        let back = try XCTUnwrap(store.boardScope)
        try await time("boardDrop(back)") {
            let plan = try await store.prepareBoardDrop(.init(scope: back, item: .notes([note.path])), target: source.value, scope: back)
            try await store.commitBoardDrop(plan, scope: back)
        }
        XCTAssertEqual(MacCollectionValues.boardValues(try XCTUnwrap(store.notes.first { $0.path == note.path }), name: scope.field), source.value.map { [$0] } ?? [])

        // Optimistic single-card move: time until the card renders in the
        // target column, then until its background write lands.
        for (from, to) in [(source.value, target), (target, source.value)] {
            let current = try XCTUnwrap(store.boardScope)
            var reviewed = false
            await time("instantMove.visible") {
                store.moveBoardCard(.init(scope: current, item: .notes([note.path])), target: to, scope: current) { _ in reviewed = true }
                _ = store.boardSnapshot
            }
            XCTAssertTrue(try XCTUnwrap(store.boardSnapshot).groups.first { $0.value == to }!.notes.contains { $0.path == note.path })
            await time("instantMove.saved") { await store.boardMoveChain?.value }
            XCTAssertFalse(reviewed)
            XCTAssertTrue(store.boardPendingMoves.isEmpty)
            XCTAssertEqual(MacCollectionValues.boardValues(try XCTUnwrap(store.notes.first { $0.path == note.path }), name: scope.field), to.map { [$0] } ?? [], "moved from \(String(describing: from))")
        }

        let imageNote = store.notes.first { $0.content.contains("![") && !$0.trashed }
        if let imageNote {
            await store.openNote(imageNote.path)
            _ = try await time("imagesSheet.snapshot", runs: 3) { try await store.imageSnapshot(workspaceID: store.workspaceID) }
            if let image = NativeInlineImage.occurrences(in: imageNote.parts.body).first(where: { URL(string: $0.reference)?.scheme == nil }) {
                _ = try await time("imagesSheet.lease", runs: 3) { try await store.imageLease(image.reference, notePath: imageNote.path, workspaceID: store.workspaceID) }
                let lease = try await store.imageLease(image.reference, notePath: imageNote.path, workspaceID: store.workspaceID)
                _ = await time("imagesSheet.decodeFull", runs: 3) { NSImage(contentsOf: lease.url)?.size }
            }
        }
    }
}
