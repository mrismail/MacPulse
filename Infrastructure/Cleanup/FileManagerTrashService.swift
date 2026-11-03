import Darwin
import Foundation
import MacPulseDomain
import MacPulseShared

/// The only place in MacPulse that removes user items (ADR-015): it moves them to the
/// Trash with `FileManager.trashItem`, so they can be put back. There is no permanent
/// deletion.
///
/// Immediately before each item, it checks again that the item exists, is not a symbolic
/// link, is the same file or folder as in the preview (device, inode, and for files size
/// and modification time) and is still allowed by the safety policy.
public struct FileManagerTrashService: TrashService {
    public init() {}

    public func moveToTrash(
        _ candidates: [CleanupCandidate],
        category: CleanupCategory,
        policy: CleanupSafetyPolicy,
        progress: @escaping @Sendable (Int) -> Void
    ) async -> CleanupReport {
        var results: [CleanupItemResult] = []
        var stopped = false
        for (index, candidate) in candidates.enumerated() {
            if Task.isCancelled {
                stopped = true
                break
            }
            let outcome = Self.move(candidate, policy: policy)
            if case .failed = outcome {
                Log.logger(.cleanup).error("Moving an item to the Trash failed")
            }
            results.append(CleanupItemResult(path: candidate.path, allocatedBytes: candidate.allocatedBytes, outcome: outcome))
            progress(index + 1)
            await Task.yield()
        }
        return CleanupReport(category: category, finishedAt: Date(), items: results, isComplete: !stopped)
    }

    public func putBack(trashPath: String, to originalPath: String, policy: CleanupSafetyPolicy) async -> PutBackFailure? {
        let trash = ScanPathPolicy.normalized(trashPath)
        let original = ScanPathPolicy.normalized(originalPath)
        // Only from a Trash folder, only to a place MacPulse could have taken it from.
        guard trash.contains("/.Trash/") || trash.contains("/.Trashes/") else { return .notInTrash }
        guard policy.verdict(for: original) == .allowed else { return .notAllowed }
        guard Self.identity(atPath: trash) != nil else { return .notInTrash }
        guard Self.identity(atPath: original) == nil else { return .originalPlaceTaken }
        let folder = (original as NSString).deletingLastPathComponent
        guard Self.identity(atPath: folder)?.isFolder == true else { return .originalFolderMissing }
        do {
            try FileManager.default.moveItem(atPath: trash, toPath: original)
            return nil
        } catch {
            return .failed((error as NSError).localizedDescription)
        }
    }

    static func move(_ candidate: CleanupCandidate, policy: CleanupSafetyPolicy) -> CleanupItemOutcome {
        guard policy.verdict(for: candidate.path) == .allowed else { return .skipped(.notAllowed) }
        guard let current = identity(atPath: candidate.path) else { return .skipped(.missing) }
        guard candidate.identity.matches(current) else { return .skipped(.changed) }
        do {
            var resulting: NSURL?
            try FileManager.default.trashItem(at: URL(fileURLWithPath: candidate.path), resultingItemURL: &resulting)
            return .movedToTrash(trashPath: resulting?.path ?? "")
        } catch {
            return .failed(message: (error as NSError).localizedDescription)
        }
    }

    /// The item's identity as `lstat` sees it; `nil` when missing. A symbolic link has its
    /// own inode, so a file swapped for a link never matches.
    public static func identity(atPath path: String) -> FileIdentity? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        let type = info.st_mode & S_IFMT
        guard type == S_IFREG || type == S_IFDIR else {
            // Links and special files are never moved: report them as changed.
            return FileIdentity(device: -1, inode: 0, size: 0, modifiedSeconds: 0, modifiedNanoseconds: 0, isFolder: false)
        }
        let isFolder = type == S_IFDIR
        return FileIdentity(
            device: Int64(info.st_dev),
            inode: UInt64(info.st_ino),
            size: isFolder ? 0 : Int64(info.st_size),
            modifiedSeconds: Int(info.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int(info.st_mtimespec.tv_nsec),
            isFolder: isFolder
        )
    }
}
