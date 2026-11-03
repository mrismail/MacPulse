import Foundation
import MacPulseDomain

#if DEBUG
/// Deterministic candidates for previews and UI tests. Never touches the disk.
public struct PreviewCleanupSource: CleanupCandidateSource {
    public init() {}

    public func candidates(for category: CleanupCategory, options: CleanupScanOptions, policy: CleanupSafetyPolicy) async -> CleanupCandidateList {
        func item(_ relative: String, _ bytes: Int64, folder: Bool, reason: String, warning: String? = nil) -> CleanupCandidate {
            CleanupCandidate(
                path: policy.homePath + "/" + relative, category: category, reason: reason, allocatedBytes: bytes,
                modified: Date(timeIntervalSince1970: 1_790_000_000),
                identity: FileIdentity(device: 1, inode: UInt64(abs(relative.hashValue) % 1_000_000), size: folder ? 0 : bytes,
                                       modifiedSeconds: 1_790_000_000, modifiedNanoseconds: 0, isFolder: folder),
                warning: warning
            )
        }
        switch category {
        case .appCaches:
            return CleanupCandidateList(category: category, candidates: [
                item("Library/Caches/com.example.browser", 1_300_000_000, folder: true, reason: "Cache kept by browser. The app rebuilds it when needed."),
                item("Library/Caches/com.example.chat", 420_000_000, folder: true, reason: "Cache kept by chat. The app rebuilds it when needed.",
                     warning: "This app is running. Quit it first so it doesn't recreate files while they are moved."),
            ])
        case .logs:
            return CleanupCandidateList(category: category, candidates: [
                item("Library/Logs/Editor", 40_000_000, folder: true, reason: "Logs written by Editor."),
            ])
        case .trash:
            return CleanupCandidateList(category: category, candidates: [], unavailableReason: "macOS lets only apps with Full Disk Access look inside the Trash. Open it in Finder to see and empty it.")
        default:
            return CleanupCandidateList(category: category, candidates: [])
        }
    }
}

/// Reports every item as moved, without touching the disk.
public struct PreviewTrashService: TrashService {
    public init() {}

    public func moveToTrash(
        _ candidates: [CleanupCandidate], category: CleanupCategory, policy: CleanupSafetyPolicy,
        progress: @escaping @Sendable (Int) -> Void
    ) async -> CleanupReport {
        let items = candidates.map {
            CleanupItemResult(path: $0.path, allocatedBytes: $0.allocatedBytes, outcome: .movedToTrash(trashPath: policy.homePath + "/.Trash/" + $0.name))
        }
        progress(items.count)
        return CleanupReport(category: category, finishedAt: Date(timeIntervalSince1970: 1_793_448_000), items: items, isComplete: true)
    }
}
#endif
