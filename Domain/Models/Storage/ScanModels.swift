import Foundation

/// What to scan and how.
public struct ScanRequest: Sendable, Equatable {
    /// Folder to scan (absolute path).
    public let rootPath: String
    public let policy: ScanPathPolicy
    public let limits: ScanLimits

    public init(rootPath: String, policy: ScanPathPolicy, limits: ScanLimits = ScanLimits()) {
        self.rootPath = rootPath
        self.policy = policy
        self.limits = limits
    }
}

/// Bounds that keep memory flat on very large trees.
public struct ScanLimits: Sendable, Equatable {
    /// Largest files kept per folder; the rest are summed into an "other files" item.
    public var filesPerFolder = 50
    /// Largest files kept for the whole scan.
    public var largestFiles = 1_000
    /// Minimum interval between progress events, seconds.
    public var progressInterval: TimeInterval = 0.1

    public init() {}
}

/// One file (or package) as seen by the scanner.
public struct ScannedFile: Sendable, Equatable {
    public let path: String
    /// Path of the folder that contains it.
    public let parentPath: String
    /// Logical size: the bytes the file says it holds.
    public let logicalBytes: Int64
    /// Size on disk: blocks allocated, hard links counted once.
    public let allocatedBytes: Int64
    public let category: FileCategory
    public let modified: Date?
    /// A bundle such as an `.app`, sized as one item.
    public let isPackage: Bool

    public init(
        path: String, parentPath: String, logicalBytes: Int64, allocatedBytes: Int64,
        category: FileCategory, modified: Date? = nil, isPackage: Bool = false
    ) {
        self.path = path
        self.parentPath = parentPath
        self.logicalBytes = logicalBytes
        self.allocatedBytes = allocatedBytes
        self.category = category
        self.modified = modified
        self.isPackage = isPackage
    }

    public var name: String { (path as NSString).lastPathComponent }
}

/// A node of the result tree: a folder, a file, a package, or the remainder of a
/// folder's smaller files.
public struct ScanNode: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case folder
        case file
        case package
        /// "N smaller files" — files not listed individually.
        case otherFiles
    }

    /// The path; for `otherFiles`, the folder path with a suffix.
    public let id: String
    public let name: String
    public let kind: Kind
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
    /// Files inside (1 for a file or package).
    public let fileCount: Int
    public let category: FileCategory?
    public let modified: Date?
    /// `nil` for leaves; folders always have an array (possibly empty).
    public let children: [ScanNode]?
    /// Set when the folder could not be read completely.
    public let isIncomplete: Bool

    public init(
        id: String, name: String, kind: Kind, logicalBytes: Int64, allocatedBytes: Int64,
        fileCount: Int, category: FileCategory? = nil, modified: Date? = nil,
        children: [ScanNode]? = nil, isIncomplete: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.logicalBytes = logicalBytes
        self.allocatedBytes = allocatedBytes
        self.fileCount = fileCount
        self.category = category
        self.modified = modified
        self.children = children
        self.isIncomplete = isIncomplete
    }

    /// The real path for folders, files and packages; `nil` for `otherFiles`.
    public var path: String? { kind == .otherFiles ? nil : id }

    /// Finds a node by id in this subtree.
    public func node(withID id: String) -> ScanNode? {
        if self.id == id { return self }
        guard let children, id.hasPrefix(self.id) else { return nil }
        for child in children {
            if let found = child.node(withID: id) { return found }
        }
        return nil
    }
}

/// Why something wasn't scanned.
public enum SkipReason: Sendable, Equatable, Codable {
    /// In the user's exclusion list.
    case excludedByUser
    /// System location MacPulse never scans (e.g. `/System`, `/dev`, VM swap).
    case systemLocation
    /// macOS asks for permission first (Desktop, Documents, Downloads, iCloud Drive,
    /// other apps' data). Skipped unless the user picked it in the folder panel.
    case protectedByPrivacy
    /// macOS refused to list it.
    case noPermission
    /// On another volume or a network share.
    case otherVolume
    /// A symbolic link or an already-visited folder (loop).
    case linkOrLoop
}

/// A location the scan did not enter.
public struct SkippedLocation: Sendable, Equatable, Identifiable {
    public var id: String { path }
    public let path: String
    public let reason: SkipReason

    public init(path: String, reason: SkipReason) {
        self.path = path
        self.reason = reason
    }
}

/// Totals for one category.
public struct CategoryTotal: Sendable, Equatable, Identifiable {
    public var id: FileCategory { category }
    public let category: FileCategory
    public let allocatedBytes: Int64
    public let logicalBytes: Int64
    public let fileCount: Int

    public init(category: FileCategory, allocatedBytes: Int64, logicalBytes: Int64, fileCount: Int) {
        self.category = category
        self.allocatedBytes = allocatedBytes
        self.logicalBytes = logicalBytes
        self.fileCount = fileCount
    }
}

/// Everything a finished (or cancelled) scan found.
public struct ScanResult: Sendable, Equatable {
    public let rootPath: String
    public let startedAt: Date
    public let finishedAt: Date
    /// `false` when the user cancelled; totals then cover only what was reached.
    public let isComplete: Bool
    public let root: ScanNode
    /// Largest files and packages across the scan, biggest first.
    public let largestFiles: [ScanNode]
    /// Biggest first.
    public let categories: [CategoryTotal]
    public let skipped: [SkippedLocation]
    public let itemsScanned: Int

    public init(
        rootPath: String, startedAt: Date, finishedAt: Date, isComplete: Bool, root: ScanNode,
        largestFiles: [ScanNode], categories: [CategoryTotal], skipped: [SkippedLocation], itemsScanned: Int
    ) {
        self.rootPath = rootPath
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.isComplete = isComplete
        self.root = root
        self.largestFiles = largestFiles
        self.categories = categories
        self.skipped = skipped
        self.itemsScanned = itemsScanned
    }

    /// Size on disk of everything scanned (measured).
    public var allocatedBytes: Metric<Int64> { .measured(root.allocatedBytes) }

    /// Caches, logs, temporary files and Trash found in this scan. An estimate: some of
    /// it may be in use, and APFS clones mean deleting can free less.
    public var recoverableBytes: Metric<Int64> {
        let bytes = categories.filter(\.category.isTypicallyRecoverable).map(\.allocatedBytes).reduce(0, +)
        return .estimated(bytes, basis: Self.recoverableBasis)
    }

    public static var recoverableBasis: String {
        String(localized: "Caches, logs, temporary files and Trash found in this scan. Some may be in use, and files that share storage (APFS clones) can free less than their size.")
    }
}

/// Live progress of a running scan.
public struct ScanProgress: Sendable, Equatable {
    public let itemsScanned: Int
    public let allocatedBytes: Int64
    /// Folder being read, for display only.
    public let currentFolder: String

    public init(itemsScanned: Int, allocatedBytes: Int64, currentFolder: String) {
        self.itemsScanned = itemsScanned
        self.allocatedBytes = allocatedBytes
        self.currentFolder = currentFolder
    }
}
