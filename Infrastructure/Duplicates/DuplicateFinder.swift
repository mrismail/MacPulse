import CryptoKit
import Darwin
import Foundation
import MacPulseDomain

/// Staged duplicate search (ADR-014):
/// 1. collect regular files with the scanner's safety rules (no links, folders once,
///    same volume, `ScanPathPolicy`; packages skipped as a unit);
/// 2. group by size, merging hard links into one stored file;
/// 3. SHA-256 of the first and last 64 KB;
/// 4. SHA-256 of the whole file;
/// 5. byte-by-byte comparison with the group's first copy.
/// Files are opened read-only with `O_NOFOLLOW`; a file whose identity, size or
/// modification time changes during the search is left out.
public struct DuplicateFinder: DuplicateScanning {
    public init() {}

    public func findDuplicates(
        _ request: DuplicateScanRequest,
        progress: @escaping @Sendable (DuplicateScanProgress) -> Void
    ) async -> DuplicateScanResult {
        let work = Task.detached(priority: .utility) {
            var search = DuplicateSearch(request: request, progress: progress)
            return search.run()
        }
        return await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
    }
}

/// One search's state. Not shared between threads.
struct DuplicateSearch {
    static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isRegularFileKey,
        .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey,
    ]
    static let edgeBytes = 64 * 1_024
    static let chunkBytes = 1_024 * 1_024

    /// What `lstat` said when the file was listed, to notice changes later.
    struct Snapshot: Equatable {
        let device: Int64
        let inode: UInt64
        let size: Int64
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
    }

    let request: DuplicateScanRequest
    let progress: @Sendable (DuplicateScanProgress) -> Void
    var statistics = DuplicateScanStatistics()
    var skipped: [SkippedLocation] = []
    var snapshots: [String: Snapshot] = [:]
    var visitedFolders = Set<Walk.FileID>()
    var cancelled = false
    var sinceCancellationCheck = 0
    let clock = ContinuousClock()
    var lastProgress: ContinuousClock.Instant
    let started = Date()

    init(request: DuplicateScanRequest, progress: @escaping @Sendable (DuplicateScanProgress) -> Void) {
        self.request = request
        self.progress = progress
        lastProgress = clock.now
    }

    mutating func run() -> DuplicateScanResult {
        var candidates: [DuplicateCandidate] = []
        for root in request.roots where !cancelled {
            collect(root: root, into: &candidates)
        }
        statistics.filesConsidered = candidates.count

        let (stored, extraLinks) = DuplicateGrouping.collapseHardLinks(candidates)
        statistics.hardLinks = extraLinks
        candidates = []
        let sameSize = DuplicateGrouping.sameSize(stored)
        statistics.sameSizeFiles = sameSize.map(\.count).reduce(0, +)

        var groups: [DuplicateGroup] = []
        // Biggest files first, so a stopped search has already found what matters most.
        let bySize = sameSize.sorted { ($0.first?.candidate.logicalBytes ?? 0) > ($1.first?.candidate.logicalBytes ?? 0) }
        let quickTotal = statistics.sameSizeFiles
        for sizeGroup in bySize {
            if cancelled { break }
            var quickHashes: [(file: DuplicateGrouping.StoredFile, hash: String)] = []
            for file in sizeGroup {
                if checkCancellation() { break }
                report(.quickHash, done: statistics.quickHashed, total: quickTotal)
                statistics.quickHashed += 1
                if let hash = hash(file, quick: true) { quickHashes.append((file, hash)) }
            }
            for quickGroup in DuplicateGrouping.buckets(quickHashes, by: { $0.hash }) {
                if cancelled { break }
                // Files of 128 KB or less were hashed whole by the quick hash.
                let wholeAlready = (quickGroup.first?.file.candidate.logicalBytes ?? 0) <= Int64(2 * Self.edgeBytes)
                let fullGroups: [[(file: DuplicateGrouping.StoredFile, hash: String)]]
                if wholeAlready {
                    fullGroups = [quickGroup]
                } else {
                    var fullHashes: [(file: DuplicateGrouping.StoredFile, hash: String)] = []
                    for entry in quickGroup {
                        if checkCancellation() { break }
                        report(.fullHash, done: statistics.fullyHashed, total: nil)
                        statistics.fullyHashed += 1
                        if let hash = hash(entry.file, quick: false) { fullHashes.append((entry.file, hash)) }
                    }
                    fullGroups = DuplicateGrouping.buckets(fullHashes, by: { $0.hash })
                }
                for sameHash in fullGroups {
                    if cancelled { break }
                    let contentHash = sameHash[0].hash
                    for verified in verify(sameHash.map(\.file)) where verified.count >= 2 {
                        groups.append(DuplicateGrouping.group(hash: contentHash, files: verified.map(withSharedBlocks)))
                    }
                }
            }
        }
        report(.verifying, done: statistics.verified, total: statistics.verified, force: true)
        return DuplicateScanResult(
            roots: request.roots, startedAt: started, finishedAt: Date(), isComplete: !cancelled,
            groups: DuplicateGrouping.ranked(groups), statistics: statistics, skipped: skipped
        )
    }

    // MARK: Collecting

    mutating func collect(root: String, into candidates: inout [DuplicateCandidate]) {
        guard let rootID = Walk.fileID(atPath: root), Walk.isDirectory(atPath: root) else {
            skipped.append(SkippedLocation(path: root, reason: .noPermission))
            return
        }
        var allowedDevices: Set<Int64> = [rootID.device]
        if root == "/", let data = Walk.fileID(atPath: "/System/Volumes/Data") {
            allowedDevices.insert(data.device)
        }
        guard visitedFolders.insert(rootID).inserted else { return }  // overlapping roots
        var stack = [root]
        while let folder = stack.popLast() {
            if checkCancellation() { return }
            stack += autoreleasepool { list(folder, allowedDevices: allowedDevices, into: &candidates) }
            report(.listing, done: candidates.count, total: nil)
        }
    }

    /// Lists one folder; returns subfolders to visit.
    mutating func list(_ folder: String, allowedDevices: Set<Int64>, into candidates: inout [DuplicateCandidate]) -> [String] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: folder, isDirectory: true), includingPropertiesForKeys: Self.keys, options: []
        ) else {
            skipped.append(SkippedLocation(path: folder, reason: .noPermission))
            return []
        }
        var subfolders: [String] = []
        for item in items {
            let path = folder == "/" ? "/" + item.lastPathComponent : folder + "/" + item.lastPathComponent
            guard let values = try? item.resourceValues(forKeys: Set(Self.keys)) else { continue }
            if values.isSymbolicLink == true { continue }  // never followed, never a copy
            if values.isDirectory == true {
                if let next = enter(path, isPackage: values.isPackage == true, allowedDevices: allowedDevices) {
                    subfolders.append(next)
                }
                continue
            }
            guard values.isRegularFile == true else { continue }
            let size = Int64(values.fileSize ?? 0)
            guard size >= request.minimumBytes else { continue }
            let category = FileCategorizer.category(forPath: path)
            if let wanted = request.categories, !wanted.contains(category) { continue }
            guard let snapshot = Self.snapshot(atPath: path) else { continue }
            snapshots[path] = snapshot
            candidates.append(DuplicateCandidate(
                path: path, logicalBytes: size, allocatedBytes: Int64(values.totalFileAllocatedSize ?? 0),
                modified: values.contentModificationDate, category: category,
                device: snapshot.device, inode: snapshot.inode
            ))
        }
        return subfolders
    }

    mutating func enter(_ path: String, isPackage: Bool, allowedDevices: Set<Int64>) -> String? {
        if case .skip(let reason) = request.policy.decision(forFolder: path) {
            skipped.append(SkippedLocation(path: path, reason: reason))
            return nil
        }
        // Packages (apps, libraries) are managed as a whole; their insides are never offered.
        if isPackage { return nil }
        guard let id = Walk.fileID(atPath: path) else { return nil }
        guard allowedDevices.contains(id.device) else {
            skipped.append(SkippedLocation(path: path, reason: .otherVolume))
            return nil
        }
        guard visitedFolders.insert(id).inserted else { return nil }
        return path
    }

    // MARK: Comparing

    /// SHA-256 (hex) of the first and last 64 KB (the whole file when small), or of the
    /// whole file. `nil` when the file can't be read or has changed.
    mutating func hash(_ file: DuplicateGrouping.StoredFile, quick: Bool) -> String? {
        let path = file.candidate.path
        guard let handle = openUnchanged(path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        let size = file.candidate.logicalBytes
        do {
            if quick {
                let head = try handle.read(upToCount: Self.edgeBytes) ?? Data()
                hasher.update(data: head)
                statistics.bytesRead += Int64(head.count)
                if size > Int64(2 * Self.edgeBytes) {
                    try handle.seek(toOffset: UInt64(size) - UInt64(Self.edgeBytes))
                    let tail = try handle.read(upToCount: Self.edgeBytes) ?? Data()
                    hasher.update(data: tail)
                    statistics.bytesRead += Int64(tail.count)
                } else if size > Int64(Self.edgeBytes) {
                    let rest = try handle.read(upToCount: Self.edgeBytes) ?? Data()
                    hasher.update(data: rest)
                    statistics.bytesRead += Int64(rest.count)
                }
            } else {
                while true {
                    if checkCancellation() { return nil }
                    let chunk = try autoreleasepool { try handle.read(upToCount: Self.chunkBytes) ?? Data() }
                    if chunk.isEmpty { break }
                    hasher.update(data: chunk)
                    statistics.bytesRead += Int64(chunk.count)
                    report(.fullHash, done: statistics.fullyHashed, total: nil)
                }
            }
        } catch {
            exclude(path, .unreadable)
            return nil
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Compares every file with the first, byte by byte. Returns groups of files that are
    /// truly identical (normally one group; more if a hash ever collided).
    mutating func verify(_ files: [DuplicateGrouping.StoredFile]) -> [[DuplicateGrouping.StoredFile]] {
        var remaining = files.filter { stillUnchanged($0.candidate.path) }
        var groups: [[DuplicateGrouping.StoredFile]] = []
        while let reference = remaining.first {
            var same = [reference]
            var different: [DuplicateGrouping.StoredFile] = []
            for other in remaining.dropFirst() {
                if cancelled { return groups }
                report(.verifying, done: statistics.verified, total: nil)
                switch compare(reference.candidate.path, other.candidate.path) {
                case .some(true): same.append(other)
                case .some(false): different.append(other)
                case .none: break  // unreadable or changed: left out
                }
            }
            if same.count >= 2, same.allSatisfy({ stillUnchanged($0.candidate.path) }) {
                statistics.verified += same.count
                groups.append(same)
            }
            remaining = different
        }
        return groups
    }

    /// `true` when identical, `false` when different, `nil` when either can't be read.
    mutating func compare(_ lhs: String, _ rhs: String) -> Bool? {
        guard let left = openUnchanged(lhs), let right = openUnchanged(rhs) else { return nil }
        defer {
            try? left.close()
            try? right.close()
        }
        do {
            while true {
                if checkCancellation() { return nil }
                let (a, b) = try autoreleasepool {
                    (try left.read(upToCount: Self.chunkBytes) ?? Data(), try right.read(upToCount: Self.chunkBytes) ?? Data())
                }
                statistics.bytesRead += Int64(a.count + b.count)
                if a != b { return false }
                if a.isEmpty { return true }
            }
        } catch {
            return nil
        }
    }

    func withSharedBlocks(_ file: DuplicateGrouping.StoredFile) -> DuplicateGrouping.StoredFile {
        let candidate = file.candidate
        guard Self.mayShareBlocks(atPath: candidate.path) else { return file }
        return DuplicateGrouping.StoredFile(
            candidate: DuplicateCandidate(
                path: candidate.path, logicalBytes: candidate.logicalBytes, allocatedBytes: candidate.allocatedBytes,
                modified: candidate.modified, category: candidate.category, device: candidate.device,
                inode: candidate.inode, mayShareBlocks: true
            ),
            otherLinks: file.otherLinks
        )
    }

    // MARK: File access

    /// Opens read-only without following a link, and only if the file is still the one
    /// that was listed (same device, inode, size and modification time).
    mutating func openUnchanged(_ path: String) -> FileHandle? {
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            exclude(path, .unreadable)
            return nil
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0, Self.snapshot(from: info) == snapshots[path] else {
            close(descriptor)
            exclude(path, .changedDuringScan)
            return nil
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    mutating func stillUnchanged(_ path: String) -> Bool {
        guard Self.snapshot(atPath: path) == snapshots[path] else {
            exclude(path, .changedDuringScan)
            return false
        }
        return true
    }

    mutating func exclude(_ path: String, _ reason: DuplicateExclusion) {
        // Count each file once.
        guard snapshots.removeValue(forKey: path) != nil else { return }
        statistics.excluded[reason, default: 0] += 1
    }

    static func snapshot(atPath path: String) -> Snapshot? {
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        return snapshot(from: info)
    }

    static func snapshot(from info: stat) -> Snapshot {
        Snapshot(
            device: Int64(info.st_dev),
            inode: UInt64(info.st_ino),
            size: Int64(info.st_size),
            modifiedSeconds: Int(info.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int(info.st_mtimespec.tv_nsec)
        )
    }

    /// APFS reports `EF_MAY_SHARE_BLOCKS` for clones; removing one may free less.
    static func mayShareBlocks(atPath path: String) -> Bool {
        // attrlist with ATTR_CMNEXT_EXT_FLAGS (0x20) in forkattr, FSOPT_ATTR_CMN_EXTENDED (0x20)
        // and FSOPT_NOFOLLOW (0x1); the buffer holds a UInt32 length then a UInt64 of flags.
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.forkattr = attrgroup_t(0x0000_0020)
        var buffer = [UInt8](repeating: 0, count: 16)
        let status = buffer.withUnsafeMutableBytes { raw in
            getattrlist(path, &list, raw.baseAddress, raw.count, UInt32(0x20 | 0x1))
        }
        guard status == 0 else { return false }
        let flags = buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt64.self) }
        return flags & 0x1 != 0  // EF_MAY_SHARE_BLOCKS
    }

    // MARK: Progress and cancellation

    mutating func checkCancellation() -> Bool {
        if cancelled { return true }
        sinceCancellationCheck += 1
        guard sinceCancellationCheck >= 64 else { return false }
        sinceCancellationCheck = 0
        cancelled = Task.isCancelled
        return cancelled
    }

    mutating func report(_ stage: DuplicateScanStage, done: Int, total: Int?, force: Bool = false) {
        let now = clock.now
        guard force || now - lastProgress >= .milliseconds(100) else { return }
        lastProgress = now
        progress(DuplicateScanProgress(stage: stage, done: done, total: total, bytesRead: statistics.bytesRead))
    }
}
