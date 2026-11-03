import AppKit
import Foundation
import MacPulseDomain

/// Lists cleanup candidates per category. Read-only: sizes come from the same safe
/// scanner as the Space Analyzer (ADR-013); nothing is opened or changed.
public struct LiveCleanupCandidateSource: CleanupCandidateSource {
    private let homePath: String
    private let scanner: any FileSystemScanning

    public init(homePath: String = NSHomeDirectory(), scanner: any FileSystemScanning = FileSystemScanner()) {
        self.homePath = ScanPathPolicy.normalized(homePath)
        self.scanner = scanner
    }

    public func candidates(
        for category: CleanupCategory,
        options: CleanupScanOptions,
        policy: CleanupSafetyPolicy
    ) async -> CleanupCandidateList {
        switch category {
        case .appCaches:
            let running = await Self.runningBundleIdentifiers()
            return await children(of: homePath + "/Library/Caches", category: category, policy: policy) { node in
                let name = node.name
                let reason = String(localized: "Cache kept by \(Self.appName(fromFolder: name)). The app rebuilds it when needed.")
                let warning = running.contains(name)
                    ? String(localized: "This app is running. Quit it first so it doesn't recreate files while they are moved.")
                    : nil
                return (reason, warning)
            }
        case .logs:
            return await children(of: homePath + "/Library/Logs", category: category, policy: policy) { node in
                (String(localized: "Logs written by \(Self.appName(fromFolder: node.name))."), nil)
            }
        case .oldDownloads:
            guard let folder = options.folder else {
                return CleanupCandidateList(category: category, candidates: [], unavailableReason: String(localized: "Choose your Downloads folder to look for old downloads."))
            }
            let cutoff = Date().addingTimeInterval(-Double(options.minimumAgeDays) * 86_400)
            let list = await children(of: folder, category: category, policy: policy, approved: true) { node in
                (String(localized: "Not changed for more than \(options.minimumAgeDays) days."), nil)
            }
            // A folder counts as old only if nothing inside it changed recently either.
            let old = list.candidates.filter { candidate in
                let newest = candidate.isFolder ? Self.newestModification(inside: candidate.path, since: cutoff) : candidate.modified
                return (newest ?? candidate.modified ?? .distantFuture) < cutoff
            }
            return CleanupCandidateList(category: category, candidates: old, note: list.note, unavailableReason: list.unavailableReason)
        case .largeFiles:
            let found = options.largeFiles.compactMap { file -> CleanupCandidate? in
                candidate(file.path, category: category, allocated: file.allocatedBytes, policy: policy,
                          reason: String(localized: "One of the largest files in your last Space Analyzer scan."))
            }
            return CleanupCandidateList(
                category: category, candidates: found,
                unavailableReason: options.largeFiles.isEmpty ? String(localized: "Scan a folder in the Space Analyzer first.") : nil
            )
        case .duplicates:
            let found = options.duplicates.compactMap { copy -> CleanupCandidate? in
                // Offered only while both copies are still what was compared; the identity
                // and the kept copy are checked again immediately before moving.
                guard let current = FileManagerTrashService.identity(atPath: copy.path), copy.identity.matches(current),
                      let kept = FileManagerTrashService.identity(atPath: copy.keptPath), copy.keptIdentity.matches(kept)
                else { return nil }
                let keptName = (copy.keptPath as NSString).lastPathComponent
                let keptFolder = (copy.keptPath as NSString).deletingLastPathComponent
                return candidate(
                    copy.path, category: category, allocated: nil, policy: policy,
                    reason: String(localized: "Identical to \(keptName) in \(keptFolder), verified byte by byte. That copy is kept."),
                    identity: copy.identity,
                    requirement: .keptCopyUnchanged(path: copy.keptPath, identity: copy.keptIdentity)
                )
            }
            return CleanupCandidateList(
                category: category, candidates: found,
                unavailableReason: options.duplicates.isEmpty ? String(localized: "Mark copies in the Duplicate Finder first.") : nil
            )
        case .emptyFolders:
            guard let folder = options.folder else {
                return CleanupCandidateList(category: category, candidates: [], unavailableReason: String(localized: "Choose a folder to look for empty folders in."))
            }
            return emptyFolders(in: ScanPathPolicy.normalized(folder), policy: policy)
        case .trash:
            return trash()
        }
    }

    // MARK: Categories

    /// The items directly inside `folder`, sized by the safe scanner.
    func children(
        of folder: String,
        category: CleanupCategory,
        policy: CleanupSafetyPolicy,
        approved: Bool = false,
        describe: @Sendable (ScanNode) -> (String, String?)
    ) async -> CleanupCandidateList {
        let request = ScanRequest(
            rootPath: folder,
            policy: ScanPathPolicy(homePath: homePath, approvedRoots: approved ? [folder] : [])
        )
        let result = await scanner.scan(request) { _ in }
        if result.root.fileCount == 0, result.skipped.contains(where: { $0.path == folder }) {
            return CleanupCandidateList(category: category, candidates: [], unavailableReason: String(localized: "MacPulse couldn't read this folder."))
        }
        let items = (result.root.children ?? []).compactMap { node -> CleanupCandidate? in
            guard let path = node.path else { return nil }  // "smaller files" summaries aren't items
            let (reason, warning) = describe(node)
            return candidate(path, category: category, allocated: node.allocatedBytes, policy: policy, reason: reason, warning: warning)
        }
        // Small files a folder summarized aren't listed individually.
        let hidden = (result.root.children ?? []).filter { $0.kind == .otherFiles }.map(\.fileCount).reduce(0, +)
        let note = hidden > 0 ? String(localized: "\(hidden) small files directly in this folder aren't listed.") : nil
        return CleanupCandidateList(category: category, candidates: items.sorted { $0.allocatedBytes > $1.allocatedBytes }, note: note)
    }

    /// Folders with nothing in them, or only a `.DS_Store`. Never follows links, stays on
    /// the volume, never enters packages.
    func emptyFolders(in root: String, policy: CleanupSafetyPolicy) -> CleanupCandidateList {
        guard let rootID = FileManagerTrashService.identity(atPath: root), rootID.isFolder else {
            return CleanupCandidateList(category: .emptyFolders, candidates: [], unavailableReason: String(localized: "MacPulse couldn't read this folder."))
        }
        let scanPolicy = ScanPathPolicy(homePath: homePath, approvedRoots: [root])
        var found: [CleanupCandidate] = []
        var stack = [root]
        var visited = Set<UInt64>()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        var allowedDevices: Set<Int64> = [rootID.device]
        if let data = FileManagerTrashService.identity(atPath: "/System/Volumes/Data") { allowedDevices.insert(data.device) }
        while let folder = stack.popLast() {
            if Task.isCancelled { break }
            autoreleasepool {
                guard let items = try? FileManager.default.contentsOfDirectory(
                    at: URL(fileURLWithPath: folder, isDirectory: true), includingPropertiesForKeys: keys, options: []
                ) else { return }
                let meaningful = items.filter { $0.lastPathComponent != ".DS_Store" }
                if meaningful.isEmpty, folder != root {
                    let reason = items.isEmpty
                        ? String(localized: "Empty folder.")
                        : String(localized: "Contains only a Finder view-settings file (.DS_Store).")
                    if let item = candidate(folder, category: .emptyFolders, allocated: 0, policy: policy, reason: reason, requirement: .stillEmpty) {
                        found.append(item)
                    }
                    return
                }
                for item in meaningful {
                    guard let values = try? item.resourceValues(forKeys: Set(keys)),
                          values.isDirectory == true, values.isSymbolicLink != true, values.isPackage != true else { continue }
                    let path = folder + "/" + item.lastPathComponent
                    guard scanPolicy.decision(forFolder: path) == .scan,
                          let id = FileManagerTrashService.identity(atPath: path),
                          allowedDevices.contains(id.device), visited.insert(id.inode).inserted else { continue }
                    stack.append(path)
                }
            }
        }
        return CleanupCandidateList(category: .emptyFolders, candidates: found.sorted { $0.path < $1.path })
    }

    func trash() -> CleanupCandidateList {
        let trash = homePath + "/.Trash"
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: trash) else {
            return CleanupCandidateList(
                category: .trash, candidates: [],
                unavailableReason: String(localized: "macOS lets only apps with Full Disk Access look inside the Trash. Open it in Finder to see and empty it.")
            )
        }
        let note = String(localized: "\(items.count) items are in the Trash. Empty it in Finder to free their space; MacPulse never deletes permanently.")
        return CleanupCandidateList(category: .trash, candidates: [], note: note)
    }

    // MARK: Helpers

    func candidate(
        _ path: String, category: CleanupCategory, allocated: Int64?, policy: CleanupSafetyPolicy,
        reason: String, warning: String? = nil, identity known: FileIdentity? = nil, requirement: CleanupRequirement? = nil
    ) -> CleanupCandidate? {
        guard policy.verdict(for: path) == .allowed,
              let current = FileManagerTrashService.identity(atPath: path), current.device >= 0 else { return nil }
        let identity = known ?? current
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey, .totalFileAllocatedSizeKey])
        return CleanupCandidate(
            path: path, category: category, reason: reason,
            allocatedBytes: allocated ?? Int64(values?.totalFileAllocatedSize ?? 0),
            modified: values?.contentModificationDate,
            identity: identity, warning: warning, requirement: requirement
        )
    }

    /// The newest modification date inside a folder, stopping early once something newer
    /// than `cutoff` is found. Links aren't followed; at most 20,000 items are looked at.
    static func newestModification(inside folder: String, since cutoff: Date) -> Date? {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: folder, isDirectory: true),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsPackageDescendants]
        ) else { return nil }
        var newest: Date?
        var seen = 0
        while let url = enumerator.nextObject() as? URL, seen < 20_000 {
            seen += 1
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { continue }
            if date > (newest ?? .distantPast) { newest = date }
            if date >= cutoff { break }
        }
        return newest
    }

    /// "com.tinyspeck.slackmacgap" → "slackmacgap"; plain names stay as they are.
    static func appName(fromFolder name: String) -> String {
        let parts = name.split(separator: ".")
        return parts.count >= 3 ? String(parts.last ?? Substring(name)) : name
    }

    static func runningBundleIdentifiers() async -> Set<String> {
        await MainActor.run {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        }
    }
}
