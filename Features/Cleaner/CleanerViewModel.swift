import Foundation
import MacPulseDomain
import MacPulseShared
import Observation

/// The Cleaner's workflow: review a category → select items → confirm → move to the
/// Trash → see what happened. `confirmCleanup()` is the only path to the Trash service,
/// and it runs only for the items the user confirmed in the dialog.
@MainActor
@Observable
public final class CleanerViewModel {
    public enum Phase: Equatable, Sendable {
        case idle
        case loading
        case reviewing
        /// Waiting for the user to confirm these items.
        case confirming([CleanupCandidate])
        case cleaning(done: Int, total: Int)
        case finished(CleanupReport)
    }

    public private(set) var selectedCategory: CleanupCategory = .appCaches
    public private(set) var phase: Phase = .idle
    public private(set) var list: CleanupCandidateList?
    /// Paths the user selected in the current list.
    public private(set) var selectedPaths: Set<String> = []
    public private(set) var history: [CleanupReport] = []
    public private(set) var historyError: AppError?

    // Options
    public private(set) var downloadsFolder: String?
    public private(set) var emptyFoldersRoot: String?
    public private(set) var minimumAgeDays = 30

    public func setMinimumAgeDays(_ days: Int) {
        guard days != minimumAgeDays else { return }
        minimumAgeDays = days
        if selectedCategory == .oldDownloads { reloadIfReviewing() }
    }

    @ObservationIgnored private let source: any CleanupCandidateSource
    @ObservationIgnored private let trash: any TrashService
    @ObservationIgnored private let historyRepository: any CleanupHistoryRepository
    @ObservationIgnored private let homePath: String
    @ObservationIgnored private let appDataPath: String?
    @ObservationIgnored private var largeFiles: @MainActor () -> [(path: String, allocatedBytes: Int64)] = { [] }
    @ObservationIgnored private var duplicates: @MainActor () -> [(path: String, keptCopy: String)] = { [] }
    @ObservationIgnored private var didClean: @MainActor (CleanupReport) async -> Void = { _ in }
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(
        source: any CleanupCandidateSource,
        trash: any TrashService,
        history: any CleanupHistoryRepository = InMemoryCleanupHistory(),
        homePath: String = NSHomeDirectory(),
        appDataPath: String? = CleanerViewModel.defaultAppDataPath()
    ) {
        self.source = source
        self.trash = trash
        historyRepository = history
        self.homePath = homePath
        self.appDataPath = appDataPath
    }

    /// Connects the other screens: where large files and marked duplicates come from, and
    /// what to refresh after a cleanup.
    public func connect(
        largeFiles: @escaping @MainActor () -> [(path: String, allocatedBytes: Int64)],
        duplicates: @escaping @MainActor () -> [(path: String, keptCopy: String)],
        didClean: @escaping @MainActor (CleanupReport) async -> Void
    ) {
        self.largeFiles = largeFiles
        self.duplicates = duplicates
        self.didClean = didClean
    }

    public static func defaultAppDataPath() -> String? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MacPulse").path
    }

    public var homeFolder: String { homePath }

    // MARK: Categories

    public func select(_ category: CleanupCategory) {
        guard category != selectedCategory || list == nil else { return }
        task?.cancel()
        selectedCategory = category
        list = nil
        selectedPaths = []
        phase = .idle
    }

    /// Opens a category and lists its candidates (used by links from other screens).
    public func open(_ category: CleanupCategory) async {
        select(category)
        await review()
    }

    public func chooseDownloadsFolder(_ path: String) {
        downloadsFolder = ScanPathPolicy.normalized(path)
        reloadIfReviewing()
    }

    public func chooseEmptyFoldersRoot(_ path: String) {
        emptyFoldersRoot = ScanPathPolicy.normalized(path)
        reloadIfReviewing()
    }

    /// `true` when the category needs a folder chosen first.
    public var needsFolder: Bool {
        switch selectedCategory {
        case .oldDownloads: downloadsFolder == nil
        case .emptyFolders: emptyFoldersRoot == nil
        default: false
        }
    }

    /// The Trash category is information only: MacPulse never deletes permanently.
    public var isReadOnlyCategory: Bool { selectedCategory == .trash }

    var policy: CleanupSafetyPolicy {
        CleanupSafetyPolicy(
            homePath: homePath,
            pickedFolders: [downloadsFolder, emptyFoldersRoot].compactMap { $0 },
            appDataPath: appDataPath
        )
    }

    // MARK: Review

    public func review() async {
        phase = .loading
        let category = selectedCategory
        let options = CleanupScanOptions(
            folder: category == .oldDownloads ? downloadsFolder : category == .emptyFolders ? emptyFoldersRoot : nil,
            minimumAgeDays: minimumAgeDays,
            largeFiles: category == .largeFiles ? largeFiles() : [],
            duplicates: category == .duplicates ? duplicates() : []
        )
        let found = await source.candidates(for: category, options: options, policy: policy)
        guard category == selectedCategory else { return }
        list = found
        // Copies marked in the Duplicate Finder were already chosen there; everything else
        // starts unselected.
        selectedPaths = category == .duplicates ? Set(found.candidates.map(\.path)) : []
        phase = .reviewing
    }

    private func reloadIfReviewing() {
        guard list != nil else { return }
        task = Task { await review() }
    }

    public var candidates: [CleanupCandidate] { list?.candidates ?? [] }

    public func isSelected(_ candidate: CleanupCandidate) -> Bool { selectedPaths.contains(candidate.path) }

    public func toggle(_ candidate: CleanupCandidate) {
        guard !isReadOnlyCategory else { return }
        if selectedPaths.contains(candidate.path) {
            selectedPaths.remove(candidate.path)
        } else {
            selectedPaths.insert(candidate.path)
        }
    }

    public func selectAll() {
        guard !isReadOnlyCategory else { return }
        selectedPaths = Set(candidates.map(\.path))
    }

    public func selectNone() {
        selectedPaths = []
    }

    public var selectedCandidates: [CleanupCandidate] { candidates.filter(isSelected) }

    /// Size on disk of the selected items (an estimate of what the Trash will hold).
    public var selectedBytes: Metric<Int64> {
        .estimated(
            selectedCandidates.map(\.allocatedBytes).reduce(0, +),
            basis: String(localized: "Sizes from the preview. The space is freed when the Trash is emptied.")
        )
    }

    // MARK: Confirm and clean

    /// Step 1: asks for confirmation. Nothing is moved yet.
    public func requestCleanup() {
        let items = selectedCandidates
        guard !items.isEmpty, !isReadOnlyCategory else { return }
        phase = .confirming(items)
    }

    public func cancelCleanup() {
        if case .confirming = phase { phase = .reviewing }
    }

    /// Step 2: the user confirmed. Moves exactly the confirmed items to the Trash.
    public func confirmCleanup() {
        guard case .confirming(let items) = phase else { return }
        let category = selectedCategory
        let policy = self.policy
        let trash = self.trash
        phase = .cleaning(done: 0, total: items.count)
        let report: @Sendable (Int) -> Void = { done in
            Task { @MainActor in self.updateProgress(done, total: items.count) }
        }
        task = Task {
            let result = await trash.moveToTrash(items, category: category, policy: policy, progress: report)
            await self.finish(result)
        }
    }

    public func stopCleanup() {
        task?.cancel()
    }

    /// Waits for the running review or cleanup (tests).
    public func waitForTask() async {
        await task?.value
    }

    private func updateProgress(_ done: Int, total: Int) {
        guard case .cleaning = phase else { return }
        phase = .cleaning(done: done, total: total)
    }

    private func finish(_ report: CleanupReport) async {
        phase = .finished(report)
        let moved = Set(report.moved.map(\.path))
        if let list {
            self.list = CleanupCandidateList(
                category: list.category,
                candidates: list.candidates.filter { !moved.contains($0.path) },
                note: list.note, unavailableReason: list.unavailableReason
            )
        }
        selectedPaths.subtract(moved)
        do {
            try await historyRepository.append(report)
        } catch {
            let appError = AppError.wrapping(error, userMessage: String(localized: "Couldn't save this cleanup to history."))
            Log.logger(.cleanup).log(appError, context: "Cleanup history")
            historyError = appError
        }
        await loadHistory()
        await didClean(report)
    }

    public func dismissResult() {
        if case .finished = phase { phase = .reviewing }
    }

    // MARK: History

    public func loadHistory() async {
        do {
            history = try await historyRepository.reports().sorted { $0.finishedAt > $1.finishedAt }
            historyError = nil
        } catch {
            let appError = AppError.wrapping(error, userMessage: String(localized: "Couldn't read cleanup history."))
            Log.logger(.cleanup).log(appError, context: "Cleanup history")
            historyError = appError
        }
    }

    public var trashPath: String { homePath + "/.Trash" }
}
