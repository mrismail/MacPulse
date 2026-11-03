import Foundation
import MacPulseDomain
import MacPulseShared
import Observation

/// What the duplicate search is doing.
public enum DuplicateSearchState: Equatable, Sendable {
    case idle
    case searching(DuplicateScanProgress)
    case finished(DuplicateScanResult)
}

/// Minimum file size for a search.
public enum DuplicateMinimumSize: Int64, CaseIterable, Identifiable, Sendable {
    case anySize = 1
    case over100KB = 100_000
    case over1MB = 1_000_000
    case over10MB = 10_000_000
    case over100MB = 100_000_000

    public var id: Int64 { rawValue }

    public var title: String {
        switch self {
        case .anySize: String(localized: "Any size")
        case .over100KB: String(localized: "Over 100 KB")
        case .over1MB: String(localized: "Over 1 MB")
        case .over10MB: String(localized: "Over 10 MB")
        case .over100MB: String(localized: "Over 100 MB")
        }
    }
}

@MainActor
@Observable
public final class DuplicateFinderViewModel {
    // Configuration
    /// Folders to search. Picked folders are approved, so protected ones inside are read.
    public private(set) var folders: [String] = []
    public var minimumSize: DuplicateMinimumSize = .over100KB
    /// Search only this type; `nil` means all types.
    public var searchCategory: FileCategory?

    // Results
    public private(set) var state: DuplicateSearchState = .idle
    public private(set) var selection = DuplicateSelection()
    public var resultCategory: FileCategory?
    public var resultMinimumSize: DuplicateMinimumSize = .anySize
    public var locationFilter = ""

    @ObservationIgnored private let finder: any DuplicateScanning
    @ObservationIgnored private let homePath: String
    @ObservationIgnored private let exclusions: () -> [String]
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    public init(finder: any DuplicateScanning, homePath: String = NSHomeDirectory(), exclusions: @escaping () -> [String] = { [] }) {
        self.finder = finder
        self.homePath = homePath
        self.exclusions = exclusions
    }

    // MARK: Configuration

    public var homeFolder: String { homePath }

    public func addFolder(_ path: String) {
        let path = ScanPathPolicy.normalized(path)
        guard !folders.contains(path) else { return }
        folders.append(path)
    }

    public func removeFolder(_ path: String) {
        folders.removeAll { $0 == path }
    }

    public var canSearch: Bool { !folders.isEmpty && !isSearching }

    // MARK: Searching

    public var isSearching: Bool {
        if case .searching = state { return true }
        return false
    }

    public var result: DuplicateScanResult? {
        if case .finished(let result) = state { return result }
        return nil
    }

    public func search() {
        guard !folders.isEmpty, !isSearching else { return }
        searchTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        // The home folder itself doesn't approve Desktop, Documents or Downloads; a folder
        // picked in the panel does (see ScanPathPolicy).
        let picked = folders.filter { $0 != homePath }
        let request = DuplicateScanRequest(
            roots: folders,
            policy: ScanPathPolicy(homePath: homePath, userExclusions: exclusions(), approvedRoots: picked + [homePath]),
            minimumBytes: minimumSize.rawValue,
            categories: searchCategory.map { [$0] }
        )
        state = .searching(DuplicateScanProgress(stage: .listing, done: 0, total: nil, bytesRead: 0))
        let finder = finder
        let report: @Sendable (DuplicateScanProgress) -> Void = { progress in
            Task { @MainActor in self.update(progress, generation: generation) }
        }
        searchTask = Task {
            let result = await finder.findDuplicates(request, progress: report)
            guard generation == self.searchGeneration else { return }
            self.finish(result)
        }
    }

    @ObservationIgnored private var searchGeneration = 0

    public func cancelSearch() {
        searchTask?.cancel()
    }

    /// Waits for the running search (tests).
    public func waitForSearch() async {
        await searchTask?.value
    }

    private func update(_ progress: DuplicateScanProgress, generation: Int) {
        guard isSearching, generation == searchGeneration else { return }
        state = .searching(progress)
    }

    private func finish(_ result: DuplicateScanResult) {
        state = .finished(result)
        selection.retain(onlyIn: result.groups)
        searchTask = nil
    }

    // MARK: Results

    /// Groups that match the result filters, biggest savings first.
    public var groups: [DuplicateGroup] {
        let query = locationFilter.trimmingCharacters(in: .whitespaces)
        return (result?.groups ?? []).filter { group in
            (resultCategory == nil || group.category == resultCategory)
                && group.logicalBytesPerFile >= resultMinimumSize.rawValue
                && (query.isEmpty || group.files.contains { $0.path.localizedCaseInsensitiveContains(query) })
        }
    }

    public func isMarked(_ file: DuplicateFile) -> Bool { selection.isMarked(file) }

    public func canMark(_ file: DuplicateFile, in group: DuplicateGroup) -> Bool {
        selection.canMark(file, in: group)
    }

    public func toggle(_ file: DuplicateFile, in group: DuplicateGroup) {
        selection.toggle(file, in: group)
    }

    /// Marks every copy except the newest (or oldest) in the groups shown.
    public func markAllExcept(_ rule: DuplicateSelection.KeepRule) {
        selection.markAllExcept(rule, in: groups)
    }

    public func clearMarks() {
        selection.clear()
    }

    public var markedCount: Int { selection.markedCount(in: result?.groups ?? []) }

    /// Space the marked copies take on disk (copies with other hard links count as zero).
    public var markedSavings: Metric<Int64> {
        let groups = result?.groups ?? []
        let bytes = selection.savings(in: groups)
        let marked = groups.filter { group in group.files.contains(where: selection.isMarked) }
        if marked.contains(where: { !$0.potentialSavings.isMeasured }) {
            return .estimated(bytes, basis: DuplicateGroup.sharedBlocksBasis)
        }
        return .measured(bytes)
    }

    /// Marked copies with the copy each one duplicates (kept), for the Cleaner.
    public var markedCopies: [MarkedDuplicate] {
        (result?.groups ?? []).flatMap { group -> [MarkedDuplicate] in
            guard let kept = group.files.first(where: { !selection.isMarked($0) }), let keptIdentity = kept.identity else { return [] }
            return group.files.filter(selection.isMarked).compactMap { file in
                file.identity.map { MarkedDuplicate(path: file.path, identity: $0, keptPath: kept.path, keptIdentity: keptIdentity) }
            }
        }
    }

    /// Drops files that the Cleaner moved to the Trash; groups left with one copy disappear.
    public func forget(_ paths: Set<String>) {
        guard let result, !paths.isEmpty else { return }
        let groups = result.groups.compactMap { group -> DuplicateGroup? in
            let files = group.files.filter { !paths.contains($0.path) }
            return files.count >= 2 ? DuplicateGroup(contentHash: group.contentHash, files: files) : nil
        }
        state = .finished(DuplicateScanResult(
            roots: result.roots, startedAt: result.startedAt, finishedAt: result.finishedAt,
            isComplete: result.isComplete, groups: groups, statistics: result.statistics, skipped: result.skipped
        ))
        selection.retain(onlyIn: groups)
    }

    /// Paths of the marked copies, for Reveal in Finder.
    public var markedPaths: [String] {
        (result?.groups ?? []).flatMap(\.files).filter(selection.isMarked).map(\.path)
    }
}
