import Foundation
import MacPulseDomain
import Testing
@testable import MacPulseFeatures

/// Records every call so tests can prove nothing is moved without confirmation.
actor CleanerRecordingTrash: TrashService {
    private(set) var calls: [[String]] = []
    nonisolated func moveToTrash(
        _ candidates: [CleanupCandidate], category: CleanupCategory, policy: CleanupSafetyPolicy,
        progress: @escaping @Sendable (Int) -> Void
    ) async -> CleanupReport {
        await record(candidates.map(\.path))
        let items = candidates.enumerated().map { index, candidate in
            CleanupItemResult(
                path: candidate.path, allocatedBytes: candidate.allocatedBytes,
                outcome: index == 0 ? .movedToTrash(trashPath: "/t/" + candidate.name) : .skipped(.changed)
            )
        }
        return CleanupReport(category: category, finishedAt: Date(), items: items, isComplete: true)
    }
    private func record(_ paths: [String]) { calls.append(paths) }
}

actor CleanerRecordingSource: CleanupCandidateSource {
    private(set) var options: [CleanupScanOptions] = []
    nonisolated func candidates(for category: CleanupCategory, options: CleanupScanOptions, policy: CleanupSafetyPolicy) async -> CleanupCandidateList {
        await record(options)
        return await PreviewCleanupSource().candidates(for: category, options: options, policy: policy)
    }
    private func record(_ value: CleanupScanOptions) { options.append(value) }
}

@Suite("CleanerViewModel")
@MainActor
struct CleanerViewModelTests {
    let home = "/Users/preview"

    func reviewed(_ trash: CleanerRecordingTrash = CleanerRecordingTrash(), history: InMemoryCleanupHistory = InMemoryCleanupHistory()) async -> CleanerViewModel {
        let model = CleanerViewModel(source: PreviewCleanupSource(), trash: trash, history: history, homePath: home, appDataPath: nil)
        await model.open(.appCaches)
        return model
    }

    @Test func nothingIsSelectedOrMovedUntilTheUserConfirms() async {
        let trash = CleanerRecordingTrash()
        let model = await reviewed(trash)
        #expect(model.candidates.count == 2)
        #expect(model.selectedCandidates.isEmpty, "Nothing is pre-selected")
        model.requestCleanup()
        #expect(model.phase == .reviewing, "Nothing selected: no confirmation is asked")

        model.selectAll()
        model.requestCleanup()
        guard case .confirming(let items) = model.phase else {
            Issue.record("Expected a confirmation step")
            return
        }
        #expect(items.count == 2)
        #expect(await trash.calls.isEmpty, "Asking is not doing")

        model.cancelCleanup()
        #expect(model.phase == .reviewing)
        model.confirmCleanup()  // without a pending confirmation it does nothing
        await model.waitForTask()
        #expect(await trash.calls.isEmpty)
    }

    @Test func confirmingMovesExactlyTheConfirmedItemsAndRecordsTheResult() async throws {
        let trash = CleanerRecordingTrash()
        let history = InMemoryCleanupHistory()
        let model = await reviewed(trash, history: history)
        let first = try #require(model.candidates.first)
        model.toggle(first)
        model.requestCleanup()
        model.confirmCleanup()
        await model.waitForTask()

        #expect(await trash.calls == [[first.path]])
        guard case .finished(let report) = model.phase else {
            Issue.record("Expected a result")
            return
        }
        #expect(report.moved.map(\.path) == [first.path])
        #expect(!model.candidates.contains { $0.path == first.path }, "Moved items leave the list")
        #expect(model.history.count == 1)
        #expect(await history.reports().count == 1)
    }

    @Test func skippedItemsAreNotReportedAsMoved() async throws {
        let model = await reviewed()
        model.selectAll()
        model.requestCleanup()
        model.confirmCleanup()
        await model.waitForTask()
        guard case .finished(let report) = model.phase else {
            Issue.record("Expected a result")
            return
        }
        #expect(report.moved.count == 1)
        #expect(report.notMoved.count == 1)
        #expect(model.candidates.count == 1, "The skipped item stays in the list")
    }

    @Test func theTrashCategoryIsReadOnly() async {
        let trash = CleanerRecordingTrash()
        let model = CleanerViewModel(source: PreviewCleanupSource(), trash: trash, homePath: home, appDataPath: nil)
        await model.open(.trash)
        #expect(model.isReadOnlyCategory)
        #expect(model.list?.unavailableReason != nil)
        model.selectAll()
        model.requestCleanup()
        #expect(model.phase == .reviewing)
    }

    @Test func foldersAreNeededAndPassedForDownloadsAndEmptyFolders() async throws {
        let source = CleanerRecordingSource()
        let model = CleanerViewModel(source: source, trash: CleanerRecordingTrash(), homePath: home, appDataPath: nil)
        model.select(.oldDownloads)
        #expect(model.needsFolder)
        model.chooseDownloadsFolder(home + "/Downloads/")
        #expect(!model.needsFolder)
        model.setMinimumAgeDays(90)
        await model.review()
        let options = try #require(await source.options.last)
        #expect(options.folder == home + "/Downloads")
        #expect(options.minimumAgeDays == 90)
        #expect(model.policy.pickedFolders == [home + "/Downloads"])
    }

    @Test func otherScreensFeedLargeFilesAndDuplicatesAndAreRefreshed() async throws {
        let source = CleanerRecordingSource()
        let model = CleanerViewModel(source: source, trash: CleanerRecordingTrash(), homePath: home, appDataPath: nil)
        var refreshed = 0
        model.connect(
            largeFiles: { [(path: "/Users/preview/Movies/big.mov", allocatedBytes: 9)] },
            duplicates: { [(path: "/Users/preview/b.jpg", keptCopy: "/Users/preview/a.jpg")] },
            didClean: { _ in refreshed += 1 }
        )
        await model.open(.largeFiles)
        #expect(await source.options.last?.largeFiles.map(\.path) == ["/Users/preview/Movies/big.mov"])
        await model.open(.duplicates)
        #expect(await source.options.last?.duplicates.map(\.path) == ["/Users/preview/b.jpg"])

        await model.open(.appCaches)
        model.selectAll()
        model.requestCleanup()
        model.confirmCleanup()
        await model.waitForTask()
        #expect(refreshed == 1, "Storage figures are refreshed after a cleanup")
    }
}
