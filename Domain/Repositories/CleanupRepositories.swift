import Foundation

/// Options for listing candidates.
public struct CleanupScanOptions: Sendable, Equatable {
    /// For old downloads and empty folders: the folder the user picked.
    public var folder: String?
    /// For old downloads: only items unchanged for at least this many days.
    public var minimumAgeDays: Int
    /// For large files: paths (with their sizes on disk) from the last Space Analyzer scan.
    public var largeFiles: [(path: String, allocatedBytes: Int64)]
    /// For duplicates: marked copies and the copy each one duplicates.
    public var duplicates: [(path: String, keptCopy: String)]

    public init(
        folder: String? = nil, minimumAgeDays: Int = 30,
        largeFiles: [(path: String, allocatedBytes: Int64)] = [],
        duplicates: [(path: String, keptCopy: String)] = []
    ) {
        self.folder = folder
        self.minimumAgeDays = minimumAgeDays
        self.largeFiles = largeFiles
        self.duplicates = duplicates
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.folder == rhs.folder && lhs.minimumAgeDays == rhs.minimumAgeDays
            && lhs.largeFiles.map(\.path) == rhs.largeFiles.map(\.path)
            && lhs.duplicates.map(\.path) == rhs.duplicates.map(\.path)
    }
}

/// Lists what a category could clean. Read-only.
public protocol CleanupCandidateSource: Sendable {
    func candidates(
        for category: CleanupCategory,
        options: CleanupScanOptions,
        policy: CleanupSafetyPolicy
    ) async -> CleanupCandidateList
}

/// Moves confirmed items to the Trash, one by one, re-validating each immediately before
/// moving it. Never deletes permanently.
public protocol TrashService: Sendable {
    func moveToTrash(
        _ candidates: [CleanupCandidate],
        category: CleanupCategory,
        policy: CleanupSafetyPolicy,
        progress: @escaping @Sendable (Int) -> Void
    ) async -> CleanupReport
}

/// Past cleanups (kept 30 days).
public protocol CleanupHistoryRepository: Sendable {
    func append(_ report: CleanupReport) async throws
    func reports() async throws -> [CleanupReport]
}

public actor InMemoryCleanupHistory: CleanupHistoryRepository {
    private var stored: [CleanupReport]
    public init(_ reports: [CleanupReport] = []) { stored = reports }
    public func append(_ report: CleanupReport) { stored.append(report) }
    public func reports() -> [CleanupReport] { stored }
}
