import Darwin
import Foundation
import MacPulseDomain

/// Walks a folder tree read-only, with the safety rules of `FileSystemScanning`:
///
/// - symbolic links are never followed (they are counted as small files);
/// - every folder is identified by device + inode and entered once, so firmlinks,
///   hard-linked folders and loops can't cause double counting or endless walks;
/// - other volumes are not entered (the startup disk's System and Data volumes are one);
/// - `ScanPathPolicy` is applied before entering each folder;
/// - hard-linked files are counted once;
/// - packages (`.app`, `.photoslibrary`, …) are sized as one item;
/// - unreadable folders are recorded, never retried, never escalated.
///
/// Only listing and metadata APIs are used; no file is opened.
public struct FileSystemScanner: FileSystemScanning {
    static let keys: [URLResourceKey] = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .isPackageKey,
        .totalFileSizeKey,
        .totalFileAllocatedSizeKey,
        .linkCountKey,
        .contentModificationDateKey,
    ]

    /// Items between cancellation checks.
    static let cancellationCheckInterval = 512

    public init() {}

    public func scan(_ request: ScanRequest, progress: @escaping @Sendable (ScanProgress) -> Void) async -> ScanResult {
        let work = Task.detached(priority: .utility) {
            var walk = Walk(request: request, progress: progress)
            return walk.run()
        }
        return await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
    }
}

/// One scan's state. Not shared between threads.
struct Walk {
    struct FileID: Hashable {
        let device: Int64
        let inode: UInt64
    }

    let request: ScanRequest
    let progress: @Sendable (ScanProgress) -> Void
    let rootPath: String
    var builder: ScanTreeBuilder
    var visitedFolders = Set<FileID>()
    var countedHardLinks = Set<FileID>()
    var allowedDevices = Set<Int64>()
    var sinceCancellationCheck = 0
    var cancelled = false
    let clock = ContinuousClock()
    var lastProgress: ContinuousClock.Instant
    let started = Date()

    init(request: ScanRequest, progress: @escaping @Sendable (ScanProgress) -> Void) {
        self.request = request
        self.progress = progress
        rootPath = ScanPathPolicy.normalized(request.rootPath)
        builder = ScanTreeBuilder(rootPath: rootPath, limits: request.limits)
        lastProgress = clock.now
    }

    mutating func run() -> ScanResult {
        guard let root = Self.fileID(atPath: rootPath), Self.isDirectory(atPath: rootPath) else {
            builder.markIncomplete(rootPath)
            builder.skip(SkippedLocation(path: rootPath, reason: .noPermission))
            return builder.build(startedAt: started, finishedAt: Date(), isComplete: true)
        }
        allowedDevices.insert(root.device)
        // The startup disk is a System volume plus a Data volume joined by firmlinks
        // (/Users, /Applications, …). Both count as "this volume" when scanning `/`.
        if rootPath == "/", let data = Self.fileID(atPath: "/System/Volumes/Data") {
            allowedDevices.insert(data.device)
        }
        visitedFolders.insert(root)

        var stack = [rootPath]
        while let folder = stack.popLast() {
            if checkCancellation() { break }
            // Listing creates autoreleased URLs and resource values; drain them per folder
            // or the whole walk's worth stays in memory until the scan ends.
            let subfolders = autoreleasepool { contents(of: folder) }
            stack += subfolders
        }
        sendProgress(folder: rootPath, force: true)
        return builder.build(startedAt: started, finishedAt: Date(), isComplete: !cancelled)
    }

    /// Lists one folder; returns the subfolders to visit.
    mutating func contents(of folder: String) -> [String] {
        let url = URL(fileURLWithPath: folder, isDirectory: true)
        let items: [URL]
        do {
            items = try FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: FileSystemScanner.keys, options: []
            )
        } catch {
            builder.markIncomplete(folder)
            builder.skip(SkippedLocation(path: folder, reason: .noPermission))
            return []
        }
        builder.addFolder(folder)
        sendProgress(folder: folder, force: false)

        var subfolders: [String] = []
        for item in items {
            if checkCancellation() { break }
            let path = folder == "/" ? "/" + item.lastPathComponent : folder + "/" + item.lastPathComponent
            guard let values = try? item.resourceValues(forKeys: Set(FileSystemScanner.keys)) else {
                builder.markIncomplete(folder)
                continue
            }
            if values.isSymbolicLink == true {
                // The link itself is a tiny file; its target is never visited.
                builder.add(file(path: path, parent: folder, values: values, category: .other))
                continue
            }
            if values.isDirectory == true {
                if let next = enter(path, isPackage: values.isPackage == true) {
                    subfolders.append(next)
                }
                continue
            }
            add(path: path, parent: folder, values: values)
        }
        return subfolders
    }

    /// Decides whether to descend into a folder. Packages are summed here and not returned.
    mutating func enter(_ path: String, isPackage: Bool) -> String? {
        switch request.policy.decision(forFolder: path) {
        case .skip(let reason):
            builder.skip(SkippedLocation(path: path, reason: reason))
            return nil
        case .scan:
            break
        }
        guard let id = Walk.fileID(atPath: path) else {
            builder.skip(SkippedLocation(path: path, reason: .noPermission))
            return nil
        }
        guard allowedDevices.contains(id.device) else {
            builder.skip(SkippedLocation(path: path, reason: .otherVolume))
            return nil
        }
        guard visitedFolders.insert(id).inserted else {
            builder.skip(SkippedLocation(path: path, reason: .linkOrLoop))
            return nil
        }
        if isPackage {
            addPackage(path)
            return nil
        }
        return path
    }

    mutating func add(path: String, parent: String, values: URLResourceValues) {
        if (values.linkCount ?? 1) > 1, let id = Walk.fileID(atPath: path),
           !countedHardLinks.insert(id).inserted {
            // Another link to a file already counted: it takes no extra space.
            builder.add(ScannedFile(
                path: path, parentPath: parent,
                logicalBytes: Int64(values.totalFileSize ?? 0), allocatedBytes: 0,
                category: FileCategorizer.category(forPath: path), modified: values.contentModificationDate
            ))
            return
        }
        builder.add(file(path: path, parent: parent, values: values, category: FileCategorizer.category(forPath: path)))
    }

    func file(path: String, parent: String, values: URLResourceValues, category: FileCategory) -> ScannedFile {
        ScannedFile(
            path: path, parentPath: parent,
            logicalBytes: Int64(values.totalFileSize ?? 0),
            allocatedBytes: Int64(values.totalFileAllocatedSize ?? 0),
            category: category,
            modified: values.contentModificationDate
        )
    }

    /// Sums a package with the same rules (no links, same volume, hard links once) and
    /// records it as one item.
    mutating func addPackage(_ path: String) {
        var totals = PackageTotals()
        var stack = [path]
        while let folder = stack.popLast() {
            if checkCancellation() { break }
            stack += autoreleasepool { sumPackageFolder(folder, into: &totals) }
        }
        let parent = (path as NSString).deletingLastPathComponent
        builder.add(ScannedFile(
            path: path, parentPath: parent, logicalBytes: totals.logical, allocatedBytes: totals.allocated,
            category: FileCategorizer.category(forPath: path, isPackage: true), isPackage: true
        ))
        if totals.incomplete { builder.markIncomplete(parent) }
    }

    struct PackageTotals {
        var logical: Int64 = 0
        var allocated: Int64 = 0
        var incomplete = false
    }

    /// Adds one folder of a package to `totals`; returns its subfolders.
    mutating func sumPackageFolder(_ folder: String, into totals: inout PackageTotals) -> [String] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: folder, isDirectory: true), includingPropertiesForKeys: FileSystemScanner.keys, options: []
        ) else {
            totals.incomplete = true
            return []
        }
        var subfolders: [String] = []
        for item in items {
            let itemPath = folder + "/" + item.lastPathComponent
            guard let values = try? item.resourceValues(forKeys: Set(FileSystemScanner.keys)) else {
                totals.incomplete = true
                continue
            }
            if values.isDirectory == true, values.isSymbolicLink != true {
                if let id = Walk.fileID(atPath: itemPath),
                   allowedDevices.contains(id.device), visitedFolders.insert(id).inserted {
                    subfolders.append(itemPath)
                }
                continue
            }
            totals.logical += Int64(values.totalFileSize ?? 0)
            if values.isSymbolicLink != true, (values.linkCount ?? 1) > 1, let id = Walk.fileID(atPath: itemPath),
               !countedHardLinks.insert(id).inserted {
                continue  // another link to a file already counted
            }
            totals.allocated += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return subfolders
    }

    // MARK: Progress and cancellation

    mutating func checkCancellation() -> Bool {
        if cancelled { return true }
        sinceCancellationCheck += 1
        guard sinceCancellationCheck >= FileSystemScanner.cancellationCheckInterval else { return false }
        sinceCancellationCheck = 0
        cancelled = Task.isCancelled
        return cancelled
    }

    mutating func sendProgress(folder: String, force: Bool) {
        let now = clock.now
        guard force || now - lastProgress >= .seconds(request.limits.progressInterval) else { return }
        lastProgress = now
        progress(ScanProgress(itemsScanned: builder.itemsScanned, allocatedBytes: builder.allocatedBytes, currentFolder: folder))
    }

    // MARK: File system

    /// Device and inode of the item itself (`lstat`: a link is not resolved).
    static func fileID(atPath path: String) -> FileID? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return FileID(device: Int64(info.st_dev), inode: UInt64(info.st_ino))
    }

    static func isDirectory(atPath path: String) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFDIR
    }
}
