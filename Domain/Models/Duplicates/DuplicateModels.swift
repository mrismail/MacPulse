import Foundation

/// What to search for duplicates and how.
public struct DuplicateScanRequest: Sendable, Equatable {
    /// Folders to search (absolute paths).
    public let roots: [String]
    public let policy: ScanPathPolicy
    /// Files smaller than this are ignored (logical size, bytes). Empty files are always ignored.
    public let minimumBytes: Int64
    /// Only these categories; `nil` means all.
    public let categories: Set<FileCategory>?

    public init(roots: [String], policy: ScanPathPolicy, minimumBytes: Int64 = 1, categories: Set<FileCategory>? = nil) {
        self.roots = roots.map(ScanPathPolicy.normalized)
        self.policy = policy
        self.minimumBytes = max(1, minimumBytes)
        self.categories = categories
    }
}

/// A regular file found while collecting candidates.
public struct DuplicateCandidate: Sendable, Equatable {
    public let path: String
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
    public let modified: Date?
    public let category: FileCategory
    /// Device and inode: two paths with the same identity are one stored file (hard links).
    public let device: Int64
    public let inode: UInt64
    /// APFS reports that the file may share blocks with another (a clone).
    public let mayShareBlocks: Bool

    public init(
        path: String, logicalBytes: Int64, allocatedBytes: Int64, modified: Date?, category: FileCategory,
        device: Int64, inode: UInt64, mayShareBlocks: Bool = false
    ) {
        self.path = path
        self.logicalBytes = logicalBytes
        self.allocatedBytes = allocatedBytes
        self.modified = modified
        self.category = category
        self.device = device
        self.inode = inode
        self.mayShareBlocks = mayShareBlocks
    }

    public var name: String { (path as NSString).lastPathComponent }
    public var folder: String { (path as NSString).deletingLastPathComponent }
}

/// One copy in a duplicate group: a stored file and every path (hard link) that reaches it.
public struct DuplicateFile: Identifiable, Sendable, Equatable {
    public var id: String { path }
    public let path: String
    /// Other paths to the same stored file (hard links). Removing one of them frees nothing.
    public let hardLinkPaths: [String]
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
    public let modified: Date?
    public let category: FileCategory
    public let mayShareBlocks: Bool

    public init(
        path: String, hardLinkPaths: [String] = [], logicalBytes: Int64, allocatedBytes: Int64,
        modified: Date?, category: FileCategory, mayShareBlocks: Bool = false
    ) {
        self.path = path
        self.hardLinkPaths = hardLinkPaths
        self.logicalBytes = logicalBytes
        self.allocatedBytes = allocatedBytes
        self.modified = modified
        self.category = category
        self.mayShareBlocks = mayShareBlocks
    }

    public var name: String { (path as NSString).lastPathComponent }
    public var folder: String { (path as NSString).deletingLastPathComponent }
}

/// Files whose contents were verified identical, byte for byte.
public struct DuplicateGroup: Identifiable, Sendable, Equatable {
    /// The SHA-256 of the contents (hex).
    public var id: String { contentHash }
    public let contentHash: String
    /// At least two copies, each a separately stored file.
    public let files: [DuplicateFile]

    public init(contentHash: String, files: [DuplicateFile]) {
        self.contentHash = contentHash
        self.files = files
    }

    /// Size of one copy (all copies have the same contents).
    public var logicalBytesPerFile: Int64 { files.first?.logicalBytes ?? 0 }

    public var category: FileCategory { files.first?.category ?? .other }

    /// Space freed by keeping one copy: size on disk of all copies but the largest.
    /// An estimate when APFS reports shared blocks (clones), which free less.
    public var potentialSavings: Metric<Int64> {
        let sizes = files.map(\.allocatedBytes)
        let bytes = sizes.reduce(0, +) - (sizes.max() ?? 0)
        if files.contains(where: \.mayShareBlocks) {
            return .estimated(bytes, basis: DuplicateGroup.sharedBlocksBasis)
        }
        return .measured(bytes)
    }

    public static var sharedBlocksBasis: String {
        String(localized: "Some copies share storage with other files (APFS clones), so removing them can free less than their size.")
    }
}

/// Why a file was left out of the comparison.
public enum DuplicateExclusion: String, Sendable, Hashable, Codable, CaseIterable {
    /// It couldn't be opened or read.
    case unreadable
    /// Its size or modification date changed while it was being compared.
    case changedDuringScan
}

/// Counts for each stage, to show how candidates were narrowed down.
public struct DuplicateScanStatistics: Sendable, Equatable {
    public var filesConsidered = 0
    public var sameSizeFiles = 0
    public var quickHashed = 0
    public var fullyHashed = 0
    public var verified = 0
    public var bytesRead: Int64 = 0
    /// Paths that are extra hard links of a file already counted.
    public var hardLinks = 0
    public var excluded: [DuplicateExclusion: Int] = [:]

    public init() {}
}

/// Everything a duplicate search found.
public struct DuplicateScanResult: Sendable, Equatable {
    public let roots: [String]
    public let startedAt: Date
    public let finishedAt: Date
    /// `false` when the user stopped the search.
    public let isComplete: Bool
    /// Biggest savings first.
    public let groups: [DuplicateGroup]
    public let statistics: DuplicateScanStatistics
    public let skipped: [SkippedLocation]

    public init(
        roots: [String], startedAt: Date, finishedAt: Date, isComplete: Bool,
        groups: [DuplicateGroup], statistics: DuplicateScanStatistics, skipped: [SkippedLocation]
    ) {
        self.roots = roots
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.isComplete = isComplete
        self.groups = groups
        self.statistics = statistics
        self.skipped = skipped
    }

    /// Copies beyond the first in every group.
    public var extraCopies: Int { groups.map { $0.files.count - 1 }.reduce(0, +) }

    /// Sum of every group's savings; an estimate if any group's is.
    public var potentialSavings: Metric<Int64> {
        let bytes = groups.compactMap(\.potentialSavings.value).reduce(0, +)
        if groups.contains(where: { !$0.potentialSavings.isMeasured }) {
            return .estimated(bytes, basis: DuplicateGroup.sharedBlocksBasis)
        }
        return .measured(bytes)
    }
}

/// The stage a duplicate search is in.
public enum DuplicateScanStage: String, Sendable, Equatable, CaseIterable {
    case listing
    case quickHash
    case fullHash
    case verifying

    public var title: String {
        switch self {
        case .listing: String(localized: "Finding files")
        case .quickHash: String(localized: "Comparing the start and end of same-size files")
        case .fullHash: String(localized: "Comparing whole contents")
        case .verifying: String(localized: "Verifying byte by byte")
        }
    }
}

public struct DuplicateScanProgress: Sendable, Equatable {
    public let stage: DuplicateScanStage
    /// Items done in this stage, and the total when known.
    public let done: Int
    public let total: Int?
    public let bytesRead: Int64

    public init(stage: DuplicateScanStage, done: Int, total: Int?, bytesRead: Int64) {
        self.stage = stage
        self.done = done
        self.total = total
        self.bytesRead = bytesRead
    }

    /// 0–1 within the stage, or `nil` while the total is unknown.
    public var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(1, Double(done) / Double(total))
    }
}
