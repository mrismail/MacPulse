import Foundation
import MacPulseDomain
import Testing
@testable import MacPulseFeatures

private actor RecordingDuplicateFinder: DuplicateScanning {
    private(set) var requests: [DuplicateScanRequest] = []
    nonisolated func findDuplicates(
        _ request: DuplicateScanRequest, progress: @escaping @Sendable (DuplicateScanProgress) -> Void
    ) async -> DuplicateScanResult {
        await record(request)
        return PreviewDuplicateFinder.result(root: request.roots.first ?? "/")
    }
    private func record(_ request: DuplicateScanRequest) { requests.append(request) }
}

private struct StoppableFinder: DuplicateScanning {
    func findDuplicates(
        _ request: DuplicateScanRequest, progress: @escaping @Sendable (DuplicateScanProgress) -> Void
    ) async -> DuplicateScanResult {
        while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
        return DuplicateScanResult(
            roots: request.roots, startedAt: Date(), finishedAt: Date(), isComplete: false,
            groups: [], statistics: DuplicateScanStatistics(), skipped: []
        )
    }
}

@Suite("DuplicateFinderViewModel")
@MainActor
struct DuplicateFinderViewModelTests {
    let home = "/Users/preview"

    func searched() async -> DuplicateFinderViewModel {
        let model = DuplicateFinderViewModel(finder: PreviewDuplicateFinder(), homePath: home)
        model.addFolder(home)
        model.search()
        await model.waitForSearch()
        return model
    }

    @Test func needsAFolderBeforeSearching() {
        let model = DuplicateFinderViewModel(finder: PreviewDuplicateFinder(), homePath: home)
        #expect(!model.canSearch)
        model.addFolder(home + "/Downloads/")
        model.addFolder(home + "/Downloads")
        #expect(model.folders == [home + "/Downloads"])
        #expect(model.canSearch)
        model.removeFolder(home + "/Downloads")
        #expect(!model.canSearch)
    }

    @Test func requestCarriesFoldersFiltersAndExclusions() async throws {
        let finder = RecordingDuplicateFinder()
        let model = DuplicateFinderViewModel(finder: finder, homePath: home, exclusions: { [self.home + "/Movies"] })
        model.addFolder(home)
        model.addFolder(home + "/Downloads")
        model.minimumSize = .over1MB
        model.searchCategory = .images
        model.search()
        await model.waitForSearch()
        let request = try #require(await finder.requests.last)
        #expect(request.roots == [home, home + "/Downloads"])
        #expect(request.minimumBytes == 1_000_000)
        #expect(request.categories == [.images])
        #expect(request.policy.userExclusions == [home + "/Movies"])
        // Picking Downloads approves it; the home folder alone doesn't approve Documents.
        #expect(request.policy.decision(forFolder: home + "/Downloads/x") == .scan)
        #expect(request.policy.decision(forFolder: home + "/Documents") == .skip(.protectedByPrivacy))
    }

    @Test func resultsAreFilteredByTypeSizeAndLocation() async {
        let model = await searched()
        #expect(model.groups.count == 3)
        model.resultCategory = .images
        #expect(model.groups.count == 1)
        model.resultCategory = nil
        model.resultMinimumSize = .over100MB
        #expect(model.groups.count == 2)
        model.resultMinimumSize = .anySize
        model.locationFilter = "old"
        #expect(model.groups.map(\.category) == [.archives])
    }

    @Test func markingKeepsOneCopyAndAddsUpSavings() async throws {
        let model = await searched()
        let video = try #require(model.groups.first { $0.category == .video })
        model.toggle(video.files[0], in: video)
        #expect(!model.canMark(video.files[1], in: video))
        model.toggle(video.files[1], in: video)
        #expect(model.markedCount == 1)
        #expect(model.markedSavings == .measured(2_400_000_000))

        model.markAllExcept(.newest)
        #expect(model.markedCount == 4)  // 1 + 2 + 1 copies
        // The photo copy with another hard link frees nothing on its own.
        let photo = try #require(model.groups.first { $0.category == .images })
        #expect(photo.files.contains { !$0.hardLinkPaths.isEmpty })
        model.clearMarks()
        #expect(model.markedCount == 0)
        #expect(model.markedPaths.isEmpty)
    }

    @Test func stoppingKeepsAPartialResult() async {
        let model = DuplicateFinderViewModel(finder: StoppableFinder(), homePath: home)
        model.addFolder(home)
        model.search()
        #expect(model.isSearching)
        model.cancelSearch()
        await model.waitForSearch()
        #expect(model.result?.isComplete == false)
    }
}
