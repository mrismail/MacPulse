import Darwin
import Foundation
import MacPulseDomain

/// Phase 4 acceptance evidence: scanning a large synthetic tree without blocking the
/// main thread, with bounded memory.
public struct ScanBenchmarkReport: Sendable, Codable, Equatable {
    public var files: Int
    public var folders: Int
    public var itemsScanned: Int
    public var secondsToCreateTree: Double
    public var secondsToScan: Double
    public var filesPerSecond: Double
    public var cpuSeconds: Double
    /// Peak memory footprint of the whole process during the run, bytes.
    public var peakFootprintBytes: UInt64
    /// Longest the main thread went without running a 10 ms heartbeat, milliseconds.
    public var maxMainThreadStallMilliseconds: Double
    public var resultIsComplete: Bool
}

/// Builds a synthetic tree in the temporary folder, scans it with the real scanner and
/// removes it again. Run as `MACPULSE_DIAGNOSTICS=1 MacPulse --macpulse-scan-benchmark`
/// (`MACPULSE_SCAN_FILES` sets the file count; default 200,000).
public enum ScanBenchmark {
    public static let launchArgument = "--macpulse-scan-benchmark"
    public static let outputPrefix = "MACPULSE_SCAN_BENCHMARK "
    public static let filesEnvironmentKey = "MACPULSE_SCAN_FILES"
    /// Every benchmark tree lives in a folder with this prefix; nothing else is removed.
    static let folderPrefix = "macpulse-scan-benchmark-"

    public static func fileCount(from environment: [String: String]) -> Int {
        environment[filesEnvironmentKey].flatMap(Int.init).map { max(1_000, min($0, 5_000_000)) } ?? 200_000
    }

    public static func run(files: Int) async -> ScanBenchmarkReport {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(folderPrefix + UUID().uuidString, isDirectory: true)
            .resolvingSymlinksInPath().path
        let clock = ContinuousClock()

        let createStart = clock.now
        let folders = createTree(at: root, files: files)
        let createSeconds = seconds(clock.now - createStart)

        let heartbeat = Heartbeat()
        let beat = Task { @MainActor in await heartbeat.run() }
        let before = ProcessTable.resourceUsage(of: getpid())
        let scanStart = clock.now
        let result = await FileSystemScanner().scan(
            ScanRequest(rootPath: root, policy: ScanPathPolicy(homePath: NSHomeDirectory(), approvedRoots: [root]))
        ) { _ in }
        let scanSeconds = seconds(clock.now - scanStart)
        let after = ProcessTable.resourceUsage(of: getpid())
        beat.cancel()
        let stall = await heartbeat.worst

        removeTree(at: root)

        let timebase = MachTimebase.current
        let ticks = { (usage: rusage_info_v4?) in (usage?.ri_user_time ?? 0) + (usage?.ri_system_time ?? 0) }
        let cpu = Double(timebase.nanoseconds(fromTicks: ticks(after) &- ticks(before))) / 1e9
        return ScanBenchmarkReport(
            files: files,
            folders: folders,
            itemsScanned: result.itemsScanned,
            secondsToCreateTree: createSeconds,
            secondsToScan: scanSeconds,
            filesPerSecond: scanSeconds > 0 ? Double(result.root.fileCount) / scanSeconds : 0,
            cpuSeconds: cpu,
            peakFootprintBytes: after?.ri_lifetime_max_phys_footprint ?? 0,
            maxMainThreadStallMilliseconds: stall,
            resultIsComplete: result.isComplete && result.root.fileCount == files
        )
    }

    public static func encode(_ report: ScanBenchmarkReport) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(report)) ?? Data("{}".utf8)
        return outputPrefix + String(decoding: data, as: UTF8.self)
    }

    // MARK: Tree

    /// 100 files per folder, 10 folders per parent. Files are sparse (sizes set with
    /// `ftruncate`), so the tree takes almost no disk space. Returns the folder count.
    static func createTree(at root: String, files: Int) -> Int {
        var created = 0
        var folders = 0
        var parent = 0
        while created < files {
            let folder = root + "/p\(parent / 10)/f\(parent % 10)"
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            folders += 1
            for index in 0..<min(100, files - created) {
                let fd = open(folder + "/file\(index).dat", O_CREAT | O_WRONLY | O_TRUNC, 0o644)
                if fd >= 0 {
                    _ = ftruncate(fd, off_t((index + 1) * 1_024))
                    close(fd)
                }
                created += 1
            }
            parent += 1
        }
        return folders + (parent + 9) / 10
    }

    /// Removes the benchmark's own tree, and only that.
    static func removeTree(at root: String) {
        guard (root as NSString).lastPathComponent.hasPrefix(folderPrefix),
              root.hasPrefix(FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path)
        else { return }
        try? FileManager.default.removeItem(atPath: root)
    }

    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

/// Measures how late a 10 ms main-actor timer fires while the scan runs.
@MainActor
private final class Heartbeat {
    private(set) var worst: Double = 0

    nonisolated init() {}

    func run() async {
        let clock = ContinuousClock()
        while !Task.isCancelled {
            let start = clock.now
            try? await Task.sleep(for: .milliseconds(10))
            worst = max(worst, ScanBenchmark.seconds(clock.now - start) * 1_000 - 10)
        }
    }
}
