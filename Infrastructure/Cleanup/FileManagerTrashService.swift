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
        // Without the identity recorded at the time (history from older versions) there is
        // no way to know the item in the Trash is the one MacPulse moved.
        guard let expected else { return .notVerifiable }
        let current: FileIdentity
        switch Self.inspect(trash) {
        case .item(let found) where found.device >= 0: current = found
        case .noAccess: return .trashNotReadable
        default: return .notInTrash
        }
        // Moving keeps the inode: anything else at that Trash path is a different item.
        if expected.device != current.device || expected.inode != current.inode {
            return .differentItem
        }
        guard Self.identity(atPath: original) == nil else { return .originalPlaceTaken }
        let folder = (original as NSString).deletingLastPathComponent
        guard Self.identity(atPath: folder)?.isFolder == true else { return .originalFolderMissing }
        if let message = Self.restore(trash, to: original) { return .failed(message) }
        return nil
    }

    /// - Parameters:
    ///   - afterMove: test hook, run right after `trashItem` returns.
    ///   - inspect: how the item in the Trash is looked at (replaced in tests).
    static func move(
        _ candidate: CleanupCandidate, policy: CleanupSafetyPolicy,
        afterMove: (String) -> Void = { _ in }, inspect: (String) -> Inspection = FileManagerTrashService.inspect
    ) -> (CleanupItemOutcome, FileIdentity?) {
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
        afterMove(trash)
        // If the item was swapped between the check and the move (for example a parent
        // folder replaced by a link), what landed in the Trash isn't the checked item:
        // move it back and report it as changed.
        switch inspect(trash) {
        case .item(let landed) where landed.device == current.device && landed.inode == current.inode:
            return (.movedToTrash(trashPath: trash), landed)
        case .noAccess:
            // Without Full Disk Access macOS may not let MacPulse look inside the Trash.
            // `trashItem` succeeded, so the checked item is there; it just can't be
            // re-checked. Moving it "back" would fail the same way.
            return (.movedToTrash(trashPath: trash), current)
        case .item, .missing:
            if restore(trash, to: candidate.path) == nil { return (.skipped(.changed), nil) }
            let name = (trash as NSString).lastPathComponent
            return (.failed(message: String(localized: "Something else reached the Trash in its place and couldn't be moved back. It's in the Trash as “\(name)”.")), nil)
        }
    }

    /// What is at a path, as `lstat` sees it.
    enum Inspection: Equatable {
        case item(FileIdentity)
        case missing
        /// macOS refused to say (no Full Disk Access for the Trash).
        case noAccess
    }

    static func inspect(_ path: String) -> Inspection {
        var info = stat()
        if lstat(path, &info) == 0 { return identity(atPath: path).map(Inspection.item) ?? .missing }
        return errno == EPERM || errno == EACCES ? .noAccess : .missing
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
        case .unchangedSince(let cutoff):
            // Something saved into an old folder after the review keeps the folder out.
            guard case .newest = FolderAge.of(candidate.path, cutoff: cutoff) else { return .changed }
            return nil
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
            && components[3] == String(getuid())
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
