import Foundation
import MacPulseDomain
import Testing
@testable import MacPulseFeatures

private actor FailingLoginItem: LoginItemControlling {
    struct Refused: Error {}
    func isEnabled() -> Bool { false }
    func setEnabled(_ enabled: Bool) throws -> Bool { throw Refused() }
}

@Suite("Settings — preferences, login item, histories")
@MainActor
struct SettingsPreferencesTests {
    func model(
        store: InMemoryPreferencesStore = InMemoryPreferencesStore(),
        login: any LoginItemControlling = InMemoryLoginItem(),
        scans: InMemoryScanHistory? = nil,
        cleanups: InMemoryCleanupHistory? = nil
    ) -> SettingsViewModel {
        SettingsViewModel(
            systemInfoRepository: PreviewSystemInfoRepository(), batteryMonitor: PreviewBatteryMonitor(),
            preferences: store, loginItem: login, scanHistory: scans, cleanupHistory: cleanups,
            confirmationDuration: .seconds(30)
        )
    }

    @Test func preferencesAreSavedAndIntervalChangesNeedARestart() {
        let store = InMemoryPreferencesStore()
        let settings = model(store: store)
        #expect(!settings.needsRestart)
        settings.update { $0.showsMenuBarExtra = false }
        #expect(store.load().showsMenuBarExtra == false)
        #expect(!settings.needsRestart, "The menu bar applies at once")
        settings.update { $0.batteryInterval = .fiveMinutes }
        #expect(settings.needsRestart)
        #expect(settings.batteryHistoryRetentionDays == 30, "Retention shown is the one in use")
        settings.update { $0.batteryRetentionDays = 999 }
        #expect(store.load().batteryRetentionDays == 30, "Values outside the choices are not saved")
    }

    @Test func openAtLoginIsOffUntilTurnedOnAndFailuresAreShown() async {
        let settings = model()
        await settings.loadLoginItem()
        #expect(!settings.opensAtLogin)
        await settings.setOpensAtLogin(true)
        #expect(settings.opensAtLogin)

        let failing = model(login: FailingLoginItem())
        await failing.setOpensAtLogin(true)
        #expect(!failing.opensAtLogin)
        #expect(failing.loginItemError != nil)
    }

    @Test func scanAndCleanupHistoryCanBeCleared() async {
        let scans = InMemoryScanHistory([ScanSummary(result: PreviewScanner.result(root: "/Users/p"))])
        let cleanups = InMemoryCleanupHistory([CleanupReport(category: .logs, finishedAt: Date(), items: [], isComplete: true)])
        let settings = model(scans: scans, cleanups: cleanups)
        #expect(settings.canClearScanHistory && settings.canClearCleanupHistory)
        await settings.clearScanHistory()
        await settings.clearCleanupHistory()
        #expect(await scans.summaries().isEmpty)
        #expect(await cleanups.reports().isEmpty)
        #expect(settings.clearScanHistoryState == .cleared)
    }
}

@Suite("Shared safety policy and Put Back")
@MainActor
struct SharedSafetyTests {
    @Test func cleanerUsesTheSameExclusionsAsScans() async {
        let model = CleanerViewModel(source: PreviewCleanupSource(), trash: PreviewTrashService(), homePath: "/Users/preview", appDataPath: nil)
        model.connect(
            largeFiles: { [] }, duplicates: { [] },
            exclusions: { ["/Users/preview/Library/Caches/com.example.chat"] },
            ageDays: (get: { 90 }, set: { _ in }),
            didClean: { _ in }
        )
        #expect(model.minimumAgeDays == 90, "The age comes from the shared setting")
        #expect(model.policy.verdict(for: "/Users/preview/Library/Caches/com.example.chat") != .allowed)
        #expect(model.policy.verdict(for: "/Users/preview/Library/Caches/com.example.browser") == .allowed)
    }

    @Test func putBackIsRecordedInHistory() async throws {
        let history = InMemoryCleanupHistory()
        let model = CleanerViewModel(source: PreviewCleanupSource(), trash: PreviewTrashService(), history: history, homePath: "/Users/preview", appDataPath: nil)
        await model.open(.appCaches)
        model.selectAll()
        model.requestCleanup()
        model.confirmCleanup()
        await model.waitForTask()
        let report = try #require(model.history.first)
        let item = try #require(report.moved.first)
        await model.putBack(item, in: report)
        #expect(model.putBackError == nil)
        let updated = try #require(await history.reports().first)
        #expect(updated.items.first { $0.path == item.path }?.outcome == .putBack)
        #expect(updated.bytesMovedToTrash < report.bytesMovedToTrash)
    }
}

@Suite("Menu bar")
struct MenuBarTests {
    @Test func labelNeverInventsACharge() {
        #expect(MenuBarPresentation.chargeText(.unavailable(.notSupportedOnThisMac)) == "—")
        #expect(MenuBarPresentation.symbol(.unavailable(.notSupportedOnThisMac), charging: false) == "gauge.with.dots.needle.50percent")
        #expect(MenuBarPresentation.symbol(.measured(10), charging: false) == "battery.0percent")
        #expect(MenuBarPresentation.symbol(.measured(55), charging: false) == "battery.50percent")
        #expect(MenuBarPresentation.symbol(.measured(55), charging: true) == "battery.100percent.bolt")
    }
}

/// Moves the first item at once, then waits until stopped.
private struct HangingTrash: TrashService {
    func moveToTrash(
        _ candidates: [CleanupCandidate], category: CleanupCategory, policy: CleanupSafetyPolicy,
        progress: @escaping @Sendable (CleanupItemResult) -> Void
    ) async -> CleanupReport {
        let first = CleanupItemResult(path: candidates[0].path, allocatedBytes: candidates[0].allocatedBytes, outcome: .movedToTrash(trashPath: "/t/a"))
        progress(first)
        while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
        return CleanupReport(category: category, finishedAt: Date(), items: [first], isComplete: false)
    }

    func putBack(trashPath: String, to originalPath: String, expected: FileIdentity?, policy: CleanupSafetyPolicy) async -> PutBackFailure? { nil }
}

private struct EndlessScanner: FileSystemScanning {
    func scan(_ request: ScanRequest, progress: @escaping @Sendable (ScanProgress) -> Void) async -> ScanResult {
        while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
        return ScanTreeBuilder(rootPath: request.rootPath).build(startedAt: Date(), finishedAt: Date(), isComplete: false)
    }
}

/// Counts history writes.
private actor CountingHistory: CleanupHistoryRepository {
    private(set) var writes = 0
    private var stored: [CleanupReport] = []
    func append(_ report: CleanupReport) { writes += 1; stored.append(report) }
    func reports() -> [CleanupReport] { stored }
    func replace(_ report: CleanupReport) throws {
        writes += 1
        guard let index = stored.firstIndex(where: { $0.id == report.id }) else { throw CleanupHistoryError.reportNotFound }
        stored[index] = report
    }
    func deleteAll() { stored.removeAll() }
}

/// Reports every item as moved, as fast as it can.
private struct InstantTrash: TrashService {
    func moveToTrash(
        _ candidates: [CleanupCandidate], category: CleanupCategory, policy: CleanupSafetyPolicy,
        progress: @escaping @Sendable (CleanupItemResult) -> Void
    ) async -> CleanupReport {
        let items = candidates.map { CleanupItemResult(path: $0.path, allocatedBytes: $0.allocatedBytes, outcome: .movedToTrash(trashPath: "/t/" + $0.name), identity: $0.identity) }
        items.forEach(progress)
        return CleanupReport(category: category, finishedAt: Date(), items: items, isComplete: true)
    }
    func putBack(trashPath: String, to originalPath: String, expected: FileIdentity?, policy: CleanupSafetyPolicy) async -> PutBackFailure? { nil }
}

private struct ManyItemsSource: CleanupCandidateSource {
    let count: Int
    func candidates(for category: CleanupCategory, options: CleanupScanOptions, policy: CleanupSafetyPolicy) async -> CleanupCandidateList {
        let items = (0..<count).map { index in
            CleanupCandidate(
                path: "/Users/preview/Library/Caches/com.example.app\(index)", category: category, reason: "test", allocatedBytes: 1,
                modified: nil, identity: FileIdentity(device: 1, inode: UInt64(index), size: 0, modifiedSeconds: 0, modifiedNanoseconds: 0, isFolder: true)
            )
        }
        return CleanupCandidateList(category: category, candidates: items)
    }
}

/// The first review is slow; later ones answer at once with a different list.
private actor SlowFirstSource: CleanupCandidateSource {
    private var calls = 0
    func candidates(for category: CleanupCategory, options: CleanupScanOptions, policy: CleanupSafetyPolicy) async -> CleanupCandidateList {
        calls += 1
        let call = calls
        if call == 1 { try? await Task.sleep(for: .milliseconds(300)) }
        let full = await PreviewCleanupSource().candidates(for: category, options: options, policy: policy)
        return CleanupCandidateList(category: category, candidates: call == 1 ? full.candidates : Array(full.candidates.prefix(1)))
    }
}

private struct EndlessDuplicateFinder: DuplicateScanning {
    func findDuplicates(_ request: DuplicateScanRequest, progress: @escaping @Sendable (DuplicateScanProgress) -> Void) async -> DuplicateScanResult {
        while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
        return DuplicateScanResult(roots: request.roots, startedAt: Date(), finishedAt: Date(), isComplete: false, groups: [], statistics: DuplicateScanStatistics(), skipped: [])
    }
}

@MainActor
private final class CallLog {
    var cleaned = 0
    var putBack: Set<String> = []
}

@Suite("Races found in the review")
@MainActor
struct ReviewRaceTests {
    @Test func historyIsSavedWhileACleanupRunsAndCategoriesStayPut() async throws {
        let history = InMemoryCleanupHistory()
        let model = CleanerViewModel(source: PreviewCleanupSource(), trash: HangingTrash(), history: history, homePath: "/Users/preview", appDataPath: nil)
        await model.open(.appCaches)
        model.selectAll()
        model.requestCleanup()
        model.confirmCleanup()
        // Wait until the first item is recorded (saves are batched, at most a second apart).
        for _ in 0..<800 {
            if (await history.reports().first?.items.count ?? 0) > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let running = try #require(await history.reports().first)
        #expect(running.items.count == 1, "What already went to the Trash is in history before the cleanup ends")
        #expect(!running.isComplete)

        model.select(.logs)
        #expect(model.selectedCategory == .appCaches, "Categories can't change during a cleanup")

        model.stopCleanup()
        await model.waitForTask()
        let reports = await history.reports()
        #expect(reports.count == 1, "The final report replaces the running one")
        #expect(reports.first?.isComplete == false)
    }

    @Test func aSecondScanCantStartWhileOneRuns() async {
        let history = InMemoryScanHistory()
        let model = SpaceAnalyzerViewModel(volumes: PreviewVolumeRepository(), scanner: EndlessScanner(), history: history, homePath: "/Users/preview")
        model.scanHomeFolder()
        model.scan("/Users/preview/Movies")
        #expect(model.isScanning)
        model.cancelScan()
        await model.waitForScan()
        #expect(model.result?.rootPath == "/Users/preview")
        #expect(model.result?.isComplete == false)
        #expect(await history.summaries().count <= 1)
    }

    @Test func spaceAnalyzerResultsDropItemsMovedToTheTrash() async throws {
        let model = SpaceAnalyzerViewModel(volumes: PreviewVolumeRepository(), scanner: PreviewScanner(), homePath: "/Users/preview")
        model.scanHomeFolder()
        await model.waitForScan()
        let biggest = try #require(model.result?.largestFiles.first?.id)
        model.forget([biggest])
        #expect(!(model.result?.largestFiles.contains { $0.id == biggest } ?? true))
        #expect(model.movedSinceScan == 1)
        model.forget([biggest])
        #expect(model.movedSinceScan == 1, "The same item isn't counted twice")
        model.restored([biggest])
        #expect(model.movedSinceScan == 0, "An item put back no longer counts as moved")
        model.forget([biggest])
        model.scanHomeFolder()
        await model.waitForScan()
        #expect(model.movedSinceScan == 0, "A new scan starts the count again")
    }

    @Test func theNewestReviewWinsAndNeverReplacesAConfirmation() async throws {
        let model = CleanerViewModel(source: SlowFirstSource(), trash: PreviewTrashService(), homePath: "/Users/preview", appDataPath: nil)
        model.select(.appCaches)
        model.startReview()          // slow, full list
        try await Task.sleep(for: .milliseconds(20))
        #expect(!model.canRequestCleanup, "Nothing can be moved while the list loads")
        await model.review()         // fast, one item
        #expect(model.candidates.count == 1)
        model.selectAll()
        model.requestCleanup()
        guard case .confirming = model.phase else {
            Issue.record("Expected the confirmation")
            return
        }
        try await Task.sleep(for: .milliseconds(400))
        #expect(model.candidates.count == 1, "The older, slower review didn't overwrite the newer one")
        guard case .confirming = model.phase else {
            Issue.record("A finishing review replaced the open confirmation")
            return
        }
    }

    @Test func aSecondDuplicateSearchCantStartAndForgetDropsCopies() async throws {
        let blocked = DuplicateFinderViewModel(finder: EndlessDuplicateFinder(), homePath: "/Users/preview")
        blocked.addFolder("/Users/preview")
        blocked.search()
        #expect(blocked.isSearching)
        blocked.addFolder("/Users/preview/Movies")
        blocked.search()
        blocked.cancelSearch()
        await blocked.waitForSearch()
        #expect(blocked.result?.roots == ["/Users/preview"], "The running search wasn't replaced")

        let model = DuplicateFinderViewModel(finder: PreviewDuplicateFinder(), homePath: "/Users/preview")
        model.addFolder("/Users/preview")
        model.search()
        await model.waitForSearch()
        let groups = try #require(model.result?.groups)
        let video = try #require(groups.first { $0.files.contains { $0.path.hasSuffix("Movies/Holiday.mov") } })
        let copy = try #require(video.files.first { $0.path.hasSuffix("Downloads/Holiday (1).mov") })
        model.forget([copy.path])
        #expect(!(model.result?.groups.contains { $0.contentHash == video.contentHash } ?? true), "A group left with one copy disappears")
        #expect(model.result?.groups.count == groups.count - 1)
    }

    @Test func historyIsSavedInBatchesAndTheFinalReportWins() async throws {
        let history = CountingHistory()
        let model = CleanerViewModel(source: ManyItemsSource(count: 500), trash: InstantTrash(), history: history, homePath: "/Users/preview", appDataPath: nil)
        await model.open(.appCaches)
        model.selectAll()
        model.requestCleanup()
        model.confirmCleanup()
        await model.waitForTask()
        let writes = await history.writes
        #expect(writes <= 500 / CleanerViewModel.itemsPerSave + 3, "Not one rewrite per item (\(writes) writes)")
        let stored = try #require(await history.reports().first)
        #expect(await history.reports().count == 1)
        #expect(stored.isComplete, "A late item result never marks a finished cleanup incomplete")
        #expect(stored.items.count == 500)
    }

    @Test func putBackRefreshesWithoutCountingAsANewCleanup() async throws {
        let model = CleanerViewModel(source: PreviewCleanupSource(), trash: PreviewTrashService(), homePath: "/Users/preview", appDataPath: nil)
        let calls = CallLog()
        model.connect(largeFiles: { [] }, duplicates: { [] }, didClean: { _ in calls.cleaned += 1 }, didPutBack: { calls.putBack.formUnion($0) })
        await model.open(.appCaches)
        model.selectAll()
        model.requestCleanup()
        model.confirmCleanup()
        await model.waitForTask()
        #expect(calls.cleaned == 1)
        let report = try #require(model.history.first)
        let item = try #require(report.moved.first)
        await model.putBack(item, in: report)
        #expect(calls.cleaned == 1, "Put Back doesn't run the after-cleanup refresh again")
        #expect(calls.putBack == [item.path])
    }
}
