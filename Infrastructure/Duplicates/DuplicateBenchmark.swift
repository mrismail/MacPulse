import Darwin
import Foundation
import MacPulseDomain

/// Phase 5 performance evidence: large groups, large files and look-alike files.
public struct DuplicateBenchmarkReport: Sendable, Codable, Equatable {
    public var filesWritten: Int
    public var bytesWritten: Int64
    public var secondsToCreate: Double
    public var secondsToSearch: Double
    public var bytesRead: Int64
    public var groupsFound: Int
    public var groupsExpected: Int
    public var largestGroup: Int
    /// Same-size files that differ only in the middle; must never be grouped.
    public var lookAlikesGrouped: Int
    public var peakFootprintBytes: UInt64
    public var maxMainThreadStallMilliseconds: Double
    public var resultIsCorrect: Bool
}

/// Writes a synthetic tree, searches it with the real `DuplicateFinder` and removes it.
/// Run as `MACPULSE_DIAGNOSTICS=1 MacPulse --macpulse-duplicate-benchmark`.
///
/// The tree: 10,000 unique 8 KB files; 500 groups of 4 identical 128 KB files; one group
/// of 4 identical 64 MB files; 200 pairs of 1 MB files that differ only in the middle;
/// and one group of 100 identical 4 KB files.
public enum DuplicateBenchmark {
    public static let launchArgument = "--macpulse-duplicate-benchmark"
    public static let outputPrefix = "MACPULSE_DUPLICATE_BENCHMARK "
    static let folderPrefix = "macpulse-duplicate-benchmark-"

    static let expectedGroups = 500 + 1 + 1

    public static func run() async -> DuplicateBenchmarkReport {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(folderPrefix + UUID().uuidString, isDirectory: true)
            .resolvingSymlinksInPath().path
        let clock = ContinuousClock()
        let createStart = clock.now
        let (files, bytes, lookAlikes) = createTree(at: root)
        let createSeconds = ScanBenchmark.seconds(clock.now - createStart)

        let heartbeat = Heartbeat()
        let beat = Task { @MainActor in await heartbeat.run() }
        let searchStart = clock.now
        let result = await DuplicateFinder().findDuplicates(
            DuplicateScanRequest(roots: [root], policy: ScanPathPolicy(homePath: NSHomeDirectory(), approvedRoots: [root]))
        ) { _ in }
        let searchSeconds = ScanBenchmark.seconds(clock.now - searchStart)
        let usage = ProcessTable.resourceUsage(of: getpid())
        beat.cancel()
        let stall = await heartbeat.worst
        removeTree(at: root)

        let lookAlikeGroups = result.groups.filter { group in group.files.contains { lookAlikes.contains($0.path) } }.count
        let largest = result.groups.map(\.files.count).max() ?? 0
        return DuplicateBenchmarkReport(
            filesWritten: files,
            bytesWritten: bytes,
            secondsToCreate: createSeconds,
            secondsToSearch: searchSeconds,
            bytesRead: result.statistics.bytesRead,
            groupsFound: result.groups.count,
            groupsExpected: expectedGroups,
            largestGroup: largest,
            lookAlikesGrouped: lookAlikeGroups,
            peakFootprintBytes: usage?.ri_lifetime_max_phys_footprint ?? 0,
            maxMainThreadStallMilliseconds: stall,
            resultIsCorrect: result.isComplete && result.groups.count == expectedGroups && lookAlikeGroups == 0 && largest == 100
        )
    }

    public static func encode(_ report: DuplicateBenchmarkReport) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(report)) ?? Data("{}".utf8)
        return outputPrefix + String(decoding: data, as: UTF8.self)
    }

    // MARK: Tree

    /// Returns files written, bytes written and the look-alike paths.
    static func createTree(at root: String) -> (Int, Int64, Set<String>) {
        var files = 0
        var bytes: Int64 = 0
        var lookAlikes = Set<String>()
        func write(_ relative: String, size: Int, seed: Int, flipMiddle: Bool = false) {
            let path = root + "/" + relative
            try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: path, contents: nil),
                  let handle = FileHandle(forWritingAtPath: path) else { return }
            defer { try? handle.close() }
            // xorshift, written in chunks of at most 1 MB so large files don't inflate memory.
            var state = UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15 | 1
            var written = 0
            while written < size {
              autoreleasepool {
                let count = min(1_024 * 1_024, size - written)
                var chunk = Data(count: count)
                chunk.withUnsafeMutableBytes { raw in
                    let words = raw.bindMemory(to: UInt64.self)
                    for index in words.indices {
                        state ^= state << 13
                        state ^= state >> 7
                        state ^= state << 17
                        words[index] = state
                    }
                }
                let middle = size / 2
                if flipMiddle, middle >= written, middle < written + count {
                    chunk[middle - written] ^= 0xFF
                }
                try? handle.write(contentsOf: chunk)
                written += count
              }
            }
            files += 1
            bytes += Int64(size)
            if flipMiddle || relative.hasPrefix("lookalike/") { lookAlikes.insert(path) }
        }
        for index in 0..<10_000 {
            write("unique/\(index / 500)/u\(index).dat", size: 8 * 1_024, seed: 1_000_000 + index)
        }
        for group in 0..<500 {
            for copy in 0..<4 {
                write("groups/g\(group % 25)/c\(copy)/file\(group).dat", size: 128 * 1_024, seed: 2_000_000 + group)
            }
        }
        for copy in 0..<4 {
            write("large/copy\(copy)/video.mov", size: 64 * 1_024 * 1_024, seed: 3_000_000)
        }
        for pair in 0..<200 {
            write("lookalike/a/p\(pair).bin", size: 1_024 * 1_024, seed: 4_000_000 + pair)
            write("lookalike/b/p\(pair).bin", size: 1_024 * 1_024, seed: 4_000_000 + pair, flipMiddle: true)
        }
        for copy in 0..<100 {
            write("many/\(copy).txt", size: 4 * 1_024, seed: 5_000_000)
        }
        return (files, bytes, lookAlikes)
    }

    /// Removes the benchmark's own tree, and only that.
    static func removeTree(at root: String) {
        guard (root as NSString).lastPathComponent.hasPrefix(folderPrefix),
              root.hasPrefix(FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path)
        else { return }
        try? FileManager.default.removeItem(atPath: root)
    }
}
