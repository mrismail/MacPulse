import Foundation
import MacPulseDomain
@testable import MacPulseInfrastructure
import Testing

/// Builds small real trees in a temporary folder and checks the scanner's safety rules.
@Suite("FileSystemScanner", .serialized)
struct FileSystemScannerTests {
    /// A fresh temporary folder, removed by the caller with `cleanUp`.
    static func makeRoot() throws -> String {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("macpulse-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // Real path, so results compare with what the scanner reports.
        return base.resolvingSymlinksInPath().path
    }

    static func cleanUp(_ root: String) {
        // Restore permissions changed by a test so the folder can be removed.
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root + "/locked")
        try? FileManager.default.removeItem(atPath: root)
    }

    static func write(_ path: String, bytes: Int) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0xA5, count: bytes).write(to: url)
    }

    func scan(_ root: String, policy: ScanPathPolicy? = nil) async -> ScanResult {
        let policy = policy ?? ScanPathPolicy(homePath: "/nonexistent-home", approvedRoots: [root])
        return await FileSystemScanner().scan(ScanRequest(rootPath: root, policy: policy)) { _ in }
    }

    @Test func sumsFilesAndFolders() async throws {
        let root = try Self.makeRoot()
        defer { Self.cleanUp(root) }
        try Self.write(root + "/a/one.bin", bytes: 100_000)
        try Self.write(root + "/a/b/two.bin", bytes: 50_000)
        try Self.write(root + "/three.bin", bytes: 10_000)

        let result = await scan(root)
        #expect(result.isComplete)
        #expect(result.root.fileCount == 3)
        #expect(result.root.logicalBytes == 160_000)
        #expect(result.root.allocatedBytes >= 160_000)  // blocks are rounded up
        #expect(result.root.node(withID: root + "/a")?.logicalBytes == 150_000)
        #expect(result.largestFiles.first?.id == root + "/a/one.bin")
    }

    @Test func neverFollowsSymbolicLinks() async throws {
        let root = try Self.makeRoot()
        let outside = try Self.makeRoot()
        defer { Self.cleanUp(root); Self.cleanUp(outside) }
        try Self.write(root + "/real/data.bin", bytes: 20_000)
        try Self.write(outside + "/big.bin", bytes: 500_000)
        let fm = FileManager.default
        try fm.createSymbolicLink(atPath: root + "/real/loop", withDestinationPath: root)       // loop to the root
        try fm.createSymbolicLink(atPath: root + "/elsewhere", withDestinationPath: outside)    // leaves the tree

        let result = await scan(root)
        #expect(result.isComplete)
        #expect(result.root.logicalBytes < 100_000, "Neither the loop nor the outside folder is counted")
        #expect(result.root.node(withID: root + "/real/data.bin") != nil)
        #expect(result.root.node(withID: root + "/real/loop")?.kind == .file)  // the link itself, not a folder
    }

    @Test func countsHardLinksOnce() async throws {
        let root = try Self.makeRoot()
        defer { Self.cleanUp(root) }
        try Self.write(root + "/original.bin", bytes: 200_000)
        try FileManager.default.linkItem(atPath: root + "/original.bin", toPath: root + "/copy.bin")

        let result = await scan(root)
        let original = try #require(result.root.node(withID: root + "/original.bin")?.allocatedBytes)
        let copy = try #require(result.root.node(withID: root + "/copy.bin")?.allocatedBytes)
        #expect(original + copy == result.root.allocatedBytes)
        #expect(min(original, copy) == 0, "The second link takes no extra space")
        #expect(max(original, copy) >= 200_000)
    }

    @Test func packagesAreOneItem() async throws {
        let root = try Self.makeRoot()
        defer { Self.cleanUp(root) }
        try Self.write(root + "/Tool.app/Contents/MacOS/Tool", bytes: 30_000)
        try Self.write(root + "/Tool.app/Contents/Resources/big.bin", bytes: 70_000)

        let result = await scan(root)
        let app = try #require(result.root.node(withID: root + "/Tool.app"))
        #expect(app.kind == .package)
        #expect(app.logicalBytes == 100_000)
        #expect(app.children == nil)
    }

    @Test func appliesExclusionsAndPrivacyRules() async throws {
        let root = try Self.makeRoot()
        defer { Self.cleanUp(root) }
        try Self.write(root + "/keep/a.bin", bytes: 1_000)
        try Self.write(root + "/skip/b.bin", bytes: 1_000)
        try Self.write(root + "/Documents/c.bin", bytes: 1_000)

        // The root plays the home folder: Documents is protected, and the user excluded "skip".
        let policy = ScanPathPolicy(homePath: root, userExclusions: [root + "/skip"], approvedRoots: [root])
        let result = await scan(root, policy: policy)
        #expect(result.root.logicalBytes == 1_000)
        #expect(result.skipped.contains(SkippedLocation(path: root + "/skip", reason: .excludedByUser)))
        #expect(result.skipped.contains(SkippedLocation(path: root + "/Documents", reason: .protectedByPrivacy)))
    }

    @Test func unreadableFoldersAreRecordedNotFatal() async throws {
        let root = try Self.makeRoot()
        defer { Self.cleanUp(root) }
        try Self.write(root + "/locked/secret.bin", bytes: 1_000)
        try Self.write(root + "/open.bin", bytes: 1_000)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root + "/locked")

        let result = await scan(root)
        #expect(result.isComplete)
        #expect(result.root.logicalBytes == 1_000)
        #expect(result.skipped.contains { $0.path == root + "/locked" && $0.reason == .noPermission })
        #expect(result.root.isIncomplete)
    }

    @Test func cancellationReturnsAPartialResult() async throws {
        let root = try Self.makeRoot()
        defer { Self.cleanUp(root) }
        for folder in 0..<40 {
            for file in 0..<50 {
                try Self.write(root + "/f\(folder)/x\(file).bin", bytes: 10)
            }
        }
        let task = Task { await scan(root) }
        task.cancel()
        let result = await task.value
        #expect(!result.isComplete)
        #expect(result.root.fileCount < 2_000)
    }

    @Test func missingRootIsReportedNotThrown() async {
        let result = await scan("/nonexistent-\(UUID().uuidString)")
        #expect(result.root.fileCount == 0)
        #expect(result.skipped.first?.reason == .noPermission)
    }

    @Test func reportsProgress() async throws {
        let root = try Self.makeRoot()
        defer { Self.cleanUp(root) }
        try Self.write(root + "/a.bin", bytes: 10)
        let counter = ProgressCounter()
        _ = await FileSystemScanner().scan(
            ScanRequest(rootPath: root, policy: ScanPathPolicy(homePath: "/none", approvedRoots: [root]))
        ) { counter.record($0) }
        #expect(counter.count >= 1)  // at least the final update
    }
}

private final class ProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func record(_ progress: ScanProgress) { lock.withLock { value += 1 } }
}
