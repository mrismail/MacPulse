import Darwin
import Foundation
import MacPulseDomain
import MacPulseShared

/// The only place in MacPulse that removes user items (ADR-015): it moves them to the
/// Trash with `FileManager.trashItem`, so they can be put back. There is no permanent
/// deletion.
///
/// Immediately before each item it checks again that the item exists, is not a symbolic
/// link, is the same file or folder as in the preview (device, inode, and for files size
/// and modification time), is still allowed by the safety policy, and meets its
/// requirement (a duplicate's kept copy unchanged, an empty folder still empty). After
/// the move it checks that what reached the Trash is that same item, and moves it back
/// if not.
public struct FileManagerTrashService: TrashService {
    public init() {}

    public func moveToTrash(
        _ candidates: [CleanupCandidate],
        category: CleanupCategory,
        policy: CleanupSafetyPolicy,
        progress: @escaping @Sendable (CleanupItemResult) -> Void
    ) async -> CleanupReport {
        var results: [CleanupItemResult] = []
        var stopped = false
        for candidate in candidates {
            if Task.isCancelled {
                stopped = true
                break
            }
            let (outcome, identity) = Self.move(candidate, policy: policy)
            if case .failed = outcome {
                Log.logger(.cleanup).error("Moving an item to the Trash failed")
            }
            let result = CleanupItemResult(path: candidate.path, allocatedBytes: candidate.allocatedBytes, outcome: outcome, identity: identity)
            results.append(result)
            progress(result)
            await Task.yield()
        }
        return CleanupReport(
            category: category, finishedAt: Date(), items: results, isComplete: !stopped,
            pickedFolders: policy.pickedFolders
        )
    }

    public func putBack(trashPath: String, to originalPath: String, expected: FileIdentity?, policy: CleanupSafetyPolicy) async -> PutBackFailure? {
        let trash = ScanPathPolicy.normalized(trashPath)
        let original = ScanPathPolicy.normalized(originalPath)
        // Only from this user's Trash or an external drive's Trash folder.
        guard Self.isInTrashFolder(trash, homePath: policy.homePath) else { return .notInTrash }
        guard policy.verdict(for: original) == .allowed else { return .notAllowed }
        guard let current = Self.identity(atPath: trash), current.device >= 0 else { return .notInTrash }
        // Moving keeps the inode: anything else at that Trash path is a different item.
        if let expected, expected.device != current.device || expected.inode != current.inode {
            return .differentItem
        }
        guard Self.identity(atPath: original) == nil else { return .originalPlaceTaken }
        let folder = (original as NSString).deletingLastPathComponent
        guard Self.identity(atPath: folder)?.isFolder == true else { return .originalFolderMissing }
        if let message = Self.restore(trash, to: original) { return .failed(message) }
        return nil
    }

    static func move(_ candidate: CleanupCandidate, policy: CleanupSafetyPolicy) -> (CleanupItemOutcome, FileIdentity?) {
        guard policy.verdict(for: candidate.path) == .allowed else { return (.skipped(.notAllowed), nil) }
        guard let current = identity(atPath: candidate.path) else { return (.skipped(.missing), nil) }
        guard candidate.identity.matches(current) else { return (.skipped(.changed), nil) }
        if let unmet = unmetRequirement(candidate) { return (.skipped(unmet), nil) }
        var resulting: NSURL?
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: candidate.path), resultingItemURL: &resulting)
        } catch {
            return (.failed(message: (error as NSError).localizedDescription), nil)
        }
        guard let trash = resulting?.path, !trash.isEmpty else {
            return (.failed(message: String(localized: "macOS moved the item but didn't say where; look for it in the Trash.")), nil)
        }
        // If the item was swapped between the check and the move (for example a parent
        // folder replaced by a link), what landed in the Trash isn't the checked item:
        // move it back and report it as changed.
        guard let landed = identity(atPath: trash), landed.device == current.device, landed.inode == current.inode else {
            _ = restore(trash, to: candidate.path)
            return (.skipped(.changed), nil)
        }
        return (.movedToTrash(trashPath: trash), landed)
    }

    /// `nil` when the candidate's requirement still holds.
    static func unmetRequirement(_ candidate: CleanupCandidate) -> CleanupSkipReason? {
        switch candidate.requirement {
        case nil:
            return nil
        case .keptCopyUnchanged(let path, let expected):
            guard ScanPathPolicy.normalized(path) != ScanPathPolicy.normalized(candidate.path),
                  let kept = identity(atPath: path), expected.matches(kept) else { return .keptCopyChanged }
            return nil
        case .stillEmpty:
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: candidate.path) else { return .changed }
            return items.allSatisfy { $0 == ".DS_Store" } ? nil : .notEmpty
        }
    }

    /// Moves an item from a Trash folder back to its original place. Returns an error
    /// message, or `nil` on success.
    static func restore(_ trash: String, to original: String) -> String? {
        do {
            try FileManager.default.moveItem(atPath: trash, toPath: original)
            return nil
        } catch {
            return (error as NSError).localizedDescription
        }
    }

    static func isInTrashFolder(_ path: String, homePath: String) -> Bool {
        let path = ScanPathPolicy.comparable(path)
        // This user's Trash, as macOS reports it (and as the home folder implies).
        var trashes = [homePath + "/.Trash"]
        if let userTrash = try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            trashes.append(userTrash.resolvingSymlinksInPath().path)
        }
        if trashes.contains(where: { ScanPathPolicy.path(path, isInside: ScanPathPolicy.comparable($0)) }) { return true }
        // External drives: /Volumes/<name>/.Trashes/<uid>/...
        let components = path.split(separator: "/")
        return components.count >= 5 && components[0] == "volumes" && components[2] == ".trashes"
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
