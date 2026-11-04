import Foundation

/// Options for listing candidates.
public struct CleanupScanOptions: Sendable, Equatable {
    /// For old downloads and empty folders: the folder the user picked.
    public var folder: String?
    /// For old downloads: only items unchanged for at least this many days.
    public var minimumAgeDays: Int
    /// For large files: paths (with their sizes on disk) from the last Space Analyzer scan.
    public var largeFiles: [(path: String, allocatedBytes: Int64)]
    /// For duplicates: marked copies, with the kept copy each one duplicates.
    public var duplicates: [MarkedDuplicate]

    public init(
        folder: String? = nil, minimumAgeDays: Int = 30,
        largeFiles: [(path: String, allocatedBytes: Int64)] = [],
        duplicates: [MarkedDuplicate] = []
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
        /// Called after each item with its result, so history can be saved as it happens.
        progress: @escaping @Sendable (CleanupItemResult) -> Void
    ) async -> CleanupReport

    /// Moves an item from the Trash back to where it was, only if that place is free and
    /// still allowed by the safety policy.
    /// `expected` is the identity recorded when the item was moved; a different item now at
    /// the Trash path is never moved.
    func putBack(trashPath: String, to originalPath: String, expected: FileIdentity?, policy: CleanupSafetyPolicy) async -> PutBackFailure?
}

/// Why an item couldn't be put back.
public enum CleanupHistoryError: Error, Equatable {
    /// `replace` found no stored report with that id.
    case reportNotFound
}

public enum PutBackFailure: Error, Sendable, Equatable {
    /// It is no longer in the Trash (emptied or moved).
    case notInTrash
    /// Something else is at the original place now.
    case originalPlaceTaken
    /// The folder it came from is gone.
    case originalFolderMissing
    /// The original place isn't one MacPulse may write to.
    case notAllowed
    /// The item in the Trash isn't the one MacPulse moved there.
    case differentItem
    /// History has no record of exactly which item was moved (older versions).
    case notVerifiable
    /// macOS doesn't let MacPulse look inside the Trash (no Full Disk Access).
    case trashNotReadable
    case failed(String)
}

/// Past cleanups (kept 30 days).
public protocol CleanupHistoryRepository: Sendable {
    func append(_ report: CleanupReport) async throws
    func reports() async throws -> [CleanupReport]
    /// Replaces a stored report (e.g. after an item was put back). Throws
    /// `CleanupHistoryError.reportNotFound` when no stored report has its id.
    func replace(_ report: CleanupReport) async throws
    func deleteAll() async throws
}

public actor InMemoryCleanupHistory: CleanupHistoryRepository {
    private var stored: [CleanupReport]
    public init(_ reports: [CleanupReport] = []) { stored = reports }
    public func append(_ report: CleanupReport) { stored.append(report) }
    public func reports() -> [CleanupReport] { stored }
    public func replace(_ report: CleanupReport) throws {
        guard let index = stored.firstIndex(where: { $0.id == report.id }) else { throw CleanupHistoryError.reportNotFound }
        stored[index] = report
    }
    public func deleteAll() { stored.removeAll() }
}
