import Foundation

/// Kinds of cleanup the Cleaner offers.
public enum CleanupCategory: String, CaseIterable, Sendable, Hashable, Codable, Identifiable {
    case appCaches
    case logs
    case oldDownloads
    case largeFiles
    case emptyFolders
    case duplicates
    case trash

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .appCaches: String(localized: "App Caches")
        case .logs: String(localized: "Logs")
        case .oldDownloads: String(localized: "Old Downloads")
        case .largeFiles: String(localized: "Large Files")
        case .emptyFolders: String(localized: "Empty Folders")
        case .duplicates: String(localized: "Duplicates")
        case .trash: String(localized: "Trash")
        }
    }

    public var summary: String {
        switch self {
        case .appCaches: String(localized: "Data apps keep to work faster. Apps rebuild it when needed, which can make them slower the first time.")
        case .logs: String(localized: "Diagnostic records written by apps. Rarely needed unless you are troubleshooting.")
        case .oldDownloads: String(localized: "Files in a Downloads folder you choose that haven't changed for a while.")
        case .largeFiles: String(localized: "The biggest files from your last Space Analyzer scan.")
        case .emptyFolders: String(localized: "Folders with nothing in them, in a folder you choose.")
        case .duplicates: String(localized: "Copies you marked in the Duplicate Finder. One copy of each file is always kept.")
        case .trash: String(localized: "Items already in the Trash. Space is freed when the Trash is emptied.")
        }
    }

    public var systemImage: String {
        switch self {
        case .appCaches: "archivebox"
        case .logs: "doc.plaintext"
        case .oldDownloads: "arrow.down.circle"
        case .largeFiles: "externaldrive.badge.exclamationmark"
        case .emptyFolders: "folder"
        case .duplicates: "doc.on.doc"
        case .trash: "trash"
        }
    }
}

/// What identifies a file or folder at preview time. Compared again immediately before
/// acting, so an item that was replaced, changed or turned into a link is never touched.
public struct FileIdentity: Sendable, Hashable, Codable {
    public let device: Int64
    public let inode: UInt64
    /// Logical size for files; 0 for folders (their size changes as the system works).
    public let size: Int64
    public let modifiedSeconds: Int
    public let modifiedNanoseconds: Int
    public let isFolder: Bool

    public init(device: Int64, inode: UInt64, size: Int64, modifiedSeconds: Int, modifiedNanoseconds: Int, isFolder: Bool) {
        self.device = device
        self.inode = inode
        self.size = size
        self.modifiedSeconds = modifiedSeconds
        self.modifiedNanoseconds = modifiedNanoseconds
        self.isFolder = isFolder
    }

    /// Folders are compared by device and inode only: apps keep writing into their cache
    /// folders, which changes the folder's date without making it a different folder.
    public func matches(_ current: FileIdentity) -> Bool {
        guard device == current.device, inode == current.inode, isFolder == current.isFolder else { return false }
        if isFolder { return true }
        return size == current.size && modifiedSeconds == current.modifiedSeconds && modifiedNanoseconds == current.modifiedNanoseconds
    }
}

/// One item the Cleaner proposes, with the reason it was proposed.
public struct CleanupCandidate: Identifiable, Sendable, Hashable {
    public var id: String { path }
    public let path: String
    public let category: CleanupCategory
    /// Why it was identified, in plain words.
    public let reason: String
    /// Size on disk; for folders, of everything inside.
    public let allocatedBytes: Int64
    public let modified: Date?
    public let identity: FileIdentity
    /// Something to know before removing it (e.g. "Slack is running").
    public let warning: String?

    public init(
        path: String, category: CleanupCategory, reason: String, allocatedBytes: Int64,
        modified: Date?, identity: FileIdentity, warning: String? = nil
    ) {
        self.path = path
        self.category = category
        self.reason = reason
        self.allocatedBytes = allocatedBytes
        self.modified = modified
        self.identity = identity
        self.warning = warning
    }

    public var name: String { (path as NSString).lastPathComponent }
    public var isFolder: Bool { identity.isFolder }
}

/// Candidates found for a category, plus anything that limited the search.
public struct CleanupCandidateList: Sendable, Equatable {
    public let category: CleanupCategory
    public let candidates: [CleanupCandidate]
    /// Shown when the category can't be fully listed (e.g. the Trash without Full Disk Access).
    public let note: String?
    /// For the Trash: total size when readable.
    public let unavailableReason: String?

    public init(category: CleanupCategory, candidates: [CleanupCandidate], note: String? = nil, unavailableReason: String? = nil) {
        self.category = category
        self.candidates = candidates
        self.note = note
        self.unavailableReason = unavailableReason
    }

    public var totalBytes: Int64 { candidates.map(\.allocatedBytes).reduce(0, +) }
}

/// Why an item was not moved even though it was selected.
public enum CleanupSkipReason: String, Sendable, Hashable, Codable {
    /// It no longer exists.
    case missing
    /// It was changed, replaced or turned into a link since the preview.
    case changed
    /// The safety policy doesn't allow it (anymore).
    case notAllowed
}

/// What happened to one item.
public enum CleanupItemOutcome: Sendable, Hashable, Codable {
    /// In the Trash, at this path.
    case movedToTrash(trashPath: String)
    case skipped(CleanupSkipReason)
    /// macOS refused; the message explains why.
    case failed(message: String)
    /// Moved to the Trash, then put back where it was from MacPulse's cleanup history.
    case putBack

    public var isMoved: Bool {
        if case .movedToTrash = self { return true }
        return false
    }
}

public struct CleanupItemResult: Identifiable, Sendable, Hashable, Codable {
    public var id: String { path }
    public let path: String
    public let allocatedBytes: Int64
    public let outcome: CleanupItemOutcome

    public init(path: String, allocatedBytes: Int64, outcome: CleanupItemOutcome) {
        self.path = path
        self.allocatedBytes = allocatedBytes
        self.outcome = outcome
    }
}

/// The result of one confirmed cleanup, kept in history.
public struct CleanupReport: Identifiable, Sendable, Equatable, Codable {
    public var id: String { "\(category.rawValue)|\(finishedAt.timeIntervalSince1970)" }
    public let category: CleanupCategory
    public let finishedAt: Date
    public let items: [CleanupItemResult]
    /// `false` when the user stopped it; items not reached are not listed.
    public let isComplete: Bool

    public init(category: CleanupCategory, finishedAt: Date, items: [CleanupItemResult], isComplete: Bool) {
        self.category = category
        self.finishedAt = finishedAt
        self.items = items
        self.isComplete = isComplete
    }

    public var moved: [CleanupItemResult] { items.filter(\.outcome.isMoved) }
    public var notMoved: [CleanupItemResult] { items.filter { !$0.outcome.isMoved } }

    /// Size of what is now in the Trash (freed when the Trash is emptied).
    public var bytesMovedToTrash: Int64 { moved.map(\.allocatedBytes).reduce(0, +) }
}
