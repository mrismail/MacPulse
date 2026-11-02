import Foundation

/// A folder or category and its size, as stored in scan history.
public struct NamedSize: Codable, Sendable, Equatable, Identifiable {
    public var id: String { key }
    /// A path for folders, a `FileCategory` raw value for categories.
    public let key: String
    public let name: String
    public let allocatedBytes: Int64

    public init(key: String, name: String, allocatedBytes: Int64) {
        self.key = key
        self.name = name
        self.allocatedBytes = allocatedBytes
    }
}

/// What one scan found, kept in scan history. Small on purpose: no file names, only the
/// scanned folder, totals, the five biggest subfolders and category totals.
public struct ScanSummary: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(rootPath)|\(finishedAt.timeIntervalSince1970)" }
    public let rootPath: String
    public let finishedAt: Date
    public let durationSeconds: Double
    public let isComplete: Bool
    public let allocatedBytes: Int64
    public let logicalBytes: Int64
    public let fileCount: Int
    public let recoverableBytes: Int64
    public let skippedCount: Int
    public let topFolders: [NamedSize]
    public let categories: [NamedSize]

    public init(
        rootPath: String, finishedAt: Date, durationSeconds: Double, isComplete: Bool,
        allocatedBytes: Int64, logicalBytes: Int64, fileCount: Int, recoverableBytes: Int64,
        skippedCount: Int, topFolders: [NamedSize], categories: [NamedSize]
    ) {
        self.rootPath = rootPath
        self.finishedAt = finishedAt
        self.durationSeconds = durationSeconds
        self.isComplete = isComplete
        self.allocatedBytes = allocatedBytes
        self.logicalBytes = logicalBytes
        self.fileCount = fileCount
        self.recoverableBytes = recoverableBytes
        self.skippedCount = skippedCount
        self.topFolders = topFolders
        self.categories = categories
    }

    public init(result: ScanResult) {
        let folders = (result.root.children ?? [])
            .filter { $0.kind == .folder }
            .prefix(5)
            .map { NamedSize(key: $0.id, name: $0.name, allocatedBytes: $0.allocatedBytes) }
        self.init(
            rootPath: result.rootPath,
            finishedAt: result.finishedAt,
            durationSeconds: result.finishedAt.timeIntervalSince(result.startedAt),
            isComplete: result.isComplete,
            allocatedBytes: result.root.allocatedBytes,
            logicalBytes: result.root.logicalBytes,
            fileCount: result.root.fileCount,
            recoverableBytes: result.recoverableBytes.value ?? 0,
            skippedCount: result.skipped.count,
            topFolders: Array(folders),
            categories: result.categories.map {
                NamedSize(key: $0.category.rawValue, name: $0.category.title, allocatedBytes: $0.allocatedBytes)
            }
        )
    }

    /// Display name of the scanned folder ("/" for the startup disk).
    public var rootName: String {
        rootPath == "/" ? "/" : (rootPath as NSString).lastPathComponent
    }
}

/// Comparisons over scan history.
public enum ScanHistory {
    /// Change in size on disk since the previous complete scan of the same folder, or
    /// `nil` when there is none (or either scan was stopped early).
    public static func change(for summary: ScanSummary, in history: [ScanSummary]) -> Int64? {
        guard summary.isComplete else { return nil }
        let previous = history
            .filter { $0.rootPath == summary.rootPath && $0.isComplete && $0.finishedAt < summary.finishedAt }
            .max { $0.finishedAt < $1.finishedAt }
        return previous.map { summary.allocatedBytes - $0.allocatedBytes }
    }

    /// Newest first, at most `limit`.
    public static func recent(_ history: [ScanSummary], limit: Int = 20) -> [ScanSummary] {
        Array(history.sorted { $0.finishedAt > $1.finishedAt }.prefix(limit))
    }
}
