import Foundation

/// Pure steps of the duplicate search. Content comparison happens in Infrastructure;
/// these functions only narrow candidates down and never compare by name or date.
public enum DuplicateGrouping {
    /// A stored file and every path that reaches it.
    public struct StoredFile: Sendable, Equatable {
        public let candidate: DuplicateCandidate
        public let otherLinks: [String]

        public init(candidate: DuplicateCandidate, otherLinks: [String] = []) {
            self.candidate = candidate
            self.otherLinks = otherLinks
        }
    }

    /// Merges paths with the same device + inode (hard links): one stored file each.
    /// Returns the stored files and how many paths were extra links.
    public static func collapseHardLinks(_ candidates: [DuplicateCandidate]) -> (files: [StoredFile], extraLinks: Int) {
        var order: [String] = []
        var byIdentity: [String: [DuplicateCandidate]] = [:]
        for candidate in candidates {
            let key = "\(candidate.device):\(candidate.inode)"
            if byIdentity[key] == nil { order.append(key) }
            byIdentity[key, default: []].append(candidate)
        }
        var extra = 0
        let files = order.compactMap { key -> StoredFile? in
            guard let links = byIdentity[key]?.sorted(by: { $0.path < $1.path }), let first = links.first else { return nil }
            extra += links.count - 1
            return StoredFile(candidate: first, otherLinks: links.dropFirst().map(\.path))
        }
        return (files, extra)
    }

    /// Groups stored files by logical size; sizes with a single file are dropped.
    public static func sameSize(_ files: [StoredFile]) -> [[StoredFile]] {
        buckets(files) { $0.candidate.logicalBytes }
    }

    /// Splits each input group by a key (for example a hash), keeping buckets of two or more.
    public static func buckets<Item, Key: Hashable>(_ items: [Item], by key: (Item) -> Key?) -> [[Item]] {
        var order: [Key] = []
        var groups: [Key: [Item]] = [:]
        for item in items {
            guard let value = key(item) else { continue }
            if groups[value] == nil { order.append(value) }
            groups[value, default: []].append(item)
        }
        return order.compactMap { groups[$0] }.filter { $0.count >= 2 }
    }

    /// Builds a verified group. Copies are listed oldest first, then by path.
    public static func group(hash: String, files: [StoredFile]) -> DuplicateGroup {
        let copies = files.map { file in
            DuplicateFile(
                path: file.candidate.path,
                hardLinkPaths: file.otherLinks,
                logicalBytes: file.candidate.logicalBytes,
                allocatedBytes: file.candidate.allocatedBytes,
                modified: file.candidate.modified,
                category: file.candidate.category,
                mayShareBlocks: file.candidate.mayShareBlocks
            )
        }
        .sorted { lhs, rhs in
            switch (lhs.modified, rhs.modified) {
            case let (left?, right?) where left != right: left < right
            default: lhs.path < rhs.path
            }
        }
        return DuplicateGroup(contentHash: hash, files: copies)
    }

    /// Biggest savings first, then by hash for a stable order.
    public static func ranked(_ groups: [DuplicateGroup]) -> [DuplicateGroup] {
        groups.sorted { lhs, rhs in
            let left = lhs.potentialSavings.value ?? 0
            let right = rhs.potentialSavings.value ?? 0
            return left != right ? left > right : lhs.contentHash < rhs.contentHash
        }
    }
}

/// Which copies the user marked for removal. Every group always keeps at least one copy.
public struct DuplicateSelection: Sendable, Equatable {
    public private(set) var markedPaths: Set<String> = []

    public init(markedPaths: Set<String> = []) {
        self.markedPaths = markedPaths
    }

    public func isMarked(_ file: DuplicateFile) -> Bool {
        markedPaths.contains(file.path)
    }

    /// A copy can be marked only while another copy in its group stays unmarked.
    public func canMark(_ file: DuplicateFile, in group: DuplicateGroup) -> Bool {
        if isMarked(file) { return true }
        return group.files.contains { $0.path != file.path && !isMarked($0) }
    }

    public mutating func toggle(_ file: DuplicateFile, in group: DuplicateGroup) {
        if isMarked(file) {
            markedPaths.remove(file.path)
        } else if canMark(file, in: group) {
            markedPaths.insert(file.path)
        }
    }

    public enum KeepRule: Sendable {
        case newest
        case oldest
    }

    /// Marks every copy except the one the rule keeps, in every group.
    public mutating func markAllExcept(_ rule: KeepRule, in groups: [DuplicateGroup]) {
        for group in groups {
            guard let keep = Self.copyToKeep(rule, in: group) else { continue }
            for file in group.files {
                if file.path == keep.path {
                    markedPaths.remove(file.path)
                } else {
                    markedPaths.insert(file.path)
                }
            }
        }
    }

    public mutating func clear() {
        markedPaths.removeAll()
    }

    /// Drops marks for files no longer in the results.
    public mutating func retain(onlyIn groups: [DuplicateGroup]) {
        let present = Set(groups.flatMap { $0.files.map(\.path) })
        markedPaths.formIntersection(present)
    }

    /// Space the marked copies take on disk. A copy with other hard links frees nothing
    /// on its own, so it counts as zero.
    public func savings(in groups: [DuplicateGroup]) -> Int64 {
        groups.flatMap(\.files)
            .filter { isMarked($0) && $0.hardLinkPaths.isEmpty }
            .map(\.allocatedBytes)
            .reduce(0, +)
    }

    public func markedCount(in groups: [DuplicateGroup]) -> Int {
        groups.flatMap(\.files).filter(isMarked).count
    }

    static func copyToKeep(_ rule: KeepRule, in group: DuplicateGroup) -> DuplicateFile? {
        let dated = group.files.sorted { lhs, rhs in
            (lhs.modified ?? .distantPast, lhs.path) < (rhs.modified ?? .distantPast, rhs.path)
        }
        return rule == .newest ? dated.last : dated.first
    }
}
