import Foundation

/// Collects scanner output and builds the result tree with bounded memory: every folder
/// is kept, but only the largest files of each folder (the rest are summed into an
/// "other files" item) and the largest files overall.
public struct ScanTreeBuilder: Sendable {
    private struct Folder: Sendable {
        var parent: String?
        var subfolders: [String] = []
        var ownLogical: Int64 = 0
        var ownAllocated: Int64 = 0
        var ownFileCount = 0
        var keptFiles: [ScannedFile] = []
        var smallestKeptIndex = 0
        var otherLogical: Int64 = 0
        var otherAllocated: Int64 = 0
        var otherCount = 0
        var isIncomplete = false
    }

    private struct Totals {
        var logical: Int64 = 0
        var allocated: Int64 = 0
        var files = 0
        var incomplete = false
    }

    public let rootPath: String
    public let limits: ScanLimits
    private var folders: [String: Folder]
    private var largest: [ScannedFile] = []
    private var smallestLargestIndex = 0
    private var categoryTotals: [FileCategory: (logical: Int64, allocated: Int64, count: Int)] = [:]
    public private(set) var skipped: [SkippedLocation] = []
    public private(set) var itemsScanned = 0
    public private(set) var allocatedBytes: Int64 = 0

    public init(rootPath: String, limits: ScanLimits = ScanLimits()) {
        let root = ScanPathPolicy.normalized(rootPath)
        self.rootPath = root
        self.limits = limits
        folders = [root: Folder(parent: nil)]
    }

    /// Registers a folder (and any missing parents up to the root).
    public mutating func addFolder(_ path: String) {
        guard folders[path] == nil, path != rootPath else { return }
        let parent = Self.parent(of: path, root: rootPath)
        addFolder(parent)
        folders[path] = Folder(parent: parent)
        folders[parent]?.subfolders.append(path)
        itemsScanned += 1
    }

    public mutating func add(_ file: ScannedFile) {
        addFolder(file.parentPath)
        itemsScanned += 1
        allocatedBytes += file.allocatedBytes

        var totals = categoryTotals[file.category] ?? (0, 0, 0)
        totals.logical += file.logicalBytes
        totals.allocated += file.allocatedBytes
        totals.count += 1
        categoryTotals[file.category] = totals

        guard var folder = folders[file.parentPath] else { return }
        folder.ownLogical += file.logicalBytes
        folder.ownAllocated += file.allocatedBytes
        folder.ownFileCount += 1
        if let dropped = Self.keep(file, in: &folder.keptFiles, smallest: &folder.smallestKeptIndex, limit: limits.filesPerFolder) {
            folder.otherLogical += dropped.logicalBytes
            folder.otherAllocated += dropped.allocatedBytes
            folder.otherCount += 1
        }
        folders[file.parentPath] = folder
        _ = Self.keep(file, in: &largest, smallest: &smallestLargestIndex, limit: limits.largestFiles)
    }

    /// The folder (or part of it) could not be read.
    public mutating func markIncomplete(_ folderPath: String) {
        addFolder(folderPath)
        folders[folderPath]?.isIncomplete = true
    }

    public mutating func skip(_ location: SkippedLocation) {
        skipped.append(location)
    }

    public func build(startedAt: Date, finishedAt: Date, isComplete: Bool) -> ScanResult {
        // Totals bottom-up: deepest folders first.
        var totals: [String: Totals] = [:]
        totals.reserveCapacity(folders.count)
        let byDepth = folders.keys.sorted { Self.depth($0) > Self.depth($1) }
        for path in byDepth {
            guard let folder = folders[path] else { continue }
            var total = totals[path] ?? Totals()
            total.logical += folder.ownLogical
            total.allocated += folder.ownAllocated
            total.files += folder.ownFileCount
            total.incomplete = total.incomplete || folder.isIncomplete
            totals[path] = total
            if let parent = folder.parent {
                var parentTotal = totals[parent] ?? Totals()
                parentTotal.logical += total.logical
                parentTotal.allocated += total.allocated
                parentTotal.files += total.files
                parentTotal.incomplete = parentTotal.incomplete || total.incomplete
                totals[parent] = parentTotal
            }
        }

        let root = node(forFolder: rootPath, totals: totals)
        let categories = categoryTotals
            .map { CategoryTotal(category: $0.key, allocatedBytes: $0.value.allocated, logicalBytes: $0.value.logical, fileCount: $0.value.count) }
            .sorted { $0.allocatedBytes != $1.allocatedBytes ? $0.allocatedBytes > $1.allocatedBytes : $0.category.rawValue < $1.category.rawValue }
        return ScanResult(
            rootPath: rootPath,
            startedAt: startedAt,
            finishedAt: finishedAt,
            isComplete: isComplete,
            root: root,
            largestFiles: largest.sorted(by: Self.biggestFirst).map(Self.node(for:)),
            categories: categories,
            skipped: skipped,
            itemsScanned: itemsScanned
        )
    }

    // MARK: Helpers

    private func node(forFolder path: String, totals: [String: Totals]) -> ScanNode {
        let folder = folders[path] ?? Folder(parent: nil)
        let total = totals[path] ?? Totals()
        var children = folder.subfolders.map { node(forFolder: $0, totals: totals) }
        children += folder.keptFiles.map(Self.node(for:))
        if folder.otherCount > 0 {
            children.append(ScanNode(
                id: path + "#other",
                name: String(localized: "\(folder.otherCount) smaller files"),
                kind: .otherFiles,
                logicalBytes: folder.otherLogical,
                allocatedBytes: folder.otherAllocated,
                fileCount: folder.otherCount
            ))
        }
        children.sort { $0.allocatedBytes != $1.allocatedBytes ? $0.allocatedBytes > $1.allocatedBytes : $0.name < $1.name }
        let name = path == "/" ? "/" : (path as NSString).lastPathComponent
        return ScanNode(
            id: path, name: name, kind: .folder,
            logicalBytes: total.logical, allocatedBytes: total.allocated, fileCount: total.files,
            children: children, isIncomplete: total.incomplete
        )
    }

    static func node(for file: ScannedFile) -> ScanNode {
        ScanNode(
            id: file.path, name: file.name, kind: file.isPackage ? .package : .file,
            logicalBytes: file.logicalBytes, allocatedBytes: file.allocatedBytes, fileCount: 1,
            category: file.category, modified: file.modified
        )
    }

    /// Keeps the `limit` largest files. Returns the file that was not kept (the new one or
    /// the one it displaced), if any.
    static func keep(_ file: ScannedFile, in kept: inout [ScannedFile], smallest: inout Int, limit: Int) -> ScannedFile? {
        guard limit > 0 else { return file }
        if kept.count < limit {
            kept.append(file)
            if kept.count == limit { smallest = indexOfSmallest(kept) }
            return nil
        }
        guard file.allocatedBytes > kept[smallest].allocatedBytes else { return file }
        let dropped = kept[smallest]
        kept[smallest] = file
        smallest = indexOfSmallest(kept)
        return dropped
    }

    static func indexOfSmallest(_ files: [ScannedFile]) -> Int {
        var index = 0
        for candidate in files.indices where files[candidate].allocatedBytes < files[index].allocatedBytes {
            index = candidate
        }
        return index
    }

    static func biggestFirst(_ lhs: ScannedFile, _ rhs: ScannedFile) -> Bool {
        lhs.allocatedBytes != rhs.allocatedBytes ? lhs.allocatedBytes > rhs.allocatedBytes : lhs.path < rhs.path
    }

    static func parent(of path: String, root: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        // Never climb above the root (a malformed path is filed under the root).
        return ScanPathPolicy.path(parent, isInside: root) ? parent : root
    }

    static func depth(_ path: String) -> Int {
        path.utf8.reduce(0) { $1 == UInt8(ascii: "/") ? $0 + 1 : $0 }
    }
}
