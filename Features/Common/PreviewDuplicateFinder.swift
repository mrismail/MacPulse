import Foundation
import MacPulseDomain

#if DEBUG
/// Deterministic duplicate results for previews and UI tests. Never touches the disk.
public struct PreviewDuplicateFinder: DuplicateScanning {
    public init() {}

    public func findDuplicates(
        _ request: DuplicateScanRequest,
        progress: @escaping @Sendable (DuplicateScanProgress) -> Void
    ) async -> DuplicateScanResult {
        progress(DuplicateScanProgress(stage: .quickHash, done: 3, total: 6, bytesRead: 1_000))
        return Self.result(root: request.roots.first ?? "/Users/preview")
    }

    public static func result(root: String, date: Date = Date(timeIntervalSince1970: 1_793_448_000)) -> DuplicateScanResult {
        func file(_ relative: String, _ bytes: Int64, _ category: FileCategory, age: TimeInterval, links: [String] = []) -> DuplicateFile {
            DuplicateFile(
                path: root + "/" + relative, hardLinkPaths: links.map { root + "/" + $0 },
                logicalBytes: bytes, allocatedBytes: bytes, modified: date.addingTimeInterval(-age), category: category
            )
        }
        let video = DuplicateGroup(contentHash: String(repeating: "a", count: 64), files: [
            file("Movies/Holiday.mov", 2_400_000_000, .video, age: 90 * 86_400),
            file("Downloads/Holiday (1).mov", 2_400_000_000, .video, age: 3 * 86_400),
        ])
        let photo = DuplicateGroup(contentHash: String(repeating: "b", count: 64), files: [
            file("Pictures/Beach.jpg", 4_200_000, .images, age: 400 * 86_400),
            file("Desktop/Beach copy.jpg", 4_200_000, .images, age: 10 * 86_400),
            file("Downloads/Beach.jpg", 4_200_000, .images, age: 2 * 86_400, links: ["Archive/Beach.jpg"]),
        ])
        let installer = DuplicateGroup(contentHash: String(repeating: "c", count: 64), files: [
            file("Downloads/Tool-2.1.dmg", 310_000_000, .archives, age: 30 * 86_400),
            file("Downloads/Old/Tool-2.1.dmg", 310_000_000, .archives, age: 60 * 86_400),
        ])
        var statistics = DuplicateScanStatistics()
        statistics.filesConsidered = 1_240
        statistics.sameSizeFiles = 18
        statistics.quickHashed = 18
        statistics.fullyHashed = 9
        statistics.verified = 7
        statistics.hardLinks = 1
        return DuplicateScanResult(
            roots: [root], startedAt: date, finishedAt: date.addingTimeInterval(6), isComplete: true,
            groups: DuplicateGrouping.ranked([video, photo, installer]), statistics: statistics, skipped: []
        )
    }
}
#endif
