import Foundation
import MacPulseDomain
@testable import MacPulseInfrastructure
import Testing

/// Real files in a temporary "home" folder. Moved items are restored from the Trash
/// location the service reports, so the tests leave nothing behind.
@Suite("Cleanup (Trash and candidates)", .serialized)
struct CleanupTests {
    typealias Tree = FileSystemScannerTests

    static func policy(_ home: String) -> CleanupSafetyPolicy {
        CleanupSafetyPolicy(homePath: home)
    }

    static func candidate(_ path: String, category: CleanupCategory = .oldDownloads) throws -> CleanupCandidate {
        let identity = try #require(FileManagerTrashService.identity(atPath: path))
        return CleanupCandidate(path: path, category: category, reason: "test", allocatedBytes: 4_096, modified: nil, identity: identity)
    }

    /// Puts trashed items back where they were (test cleanup only).
    static func restore(_ report: CleanupReport) {
        for item in report.items {
            if case .movedToTrash(let trashPath) = item.outcome, !trashPath.isEmpty {
                try? FileManager.default.moveItem(atPath: trashPath, toPath: item.path)
            }
        }
    }

    func move(_ candidates: [CleanupCandidate], home: String) async -> CleanupReport {
        await FileManagerTrashService().moveToTrash(candidates, category: .oldDownloads, policy: Self.policy(home)) { _ in }
    }

    @Test func movesToTheTrashAndReportsWhereItWent() async throws {
        let home = try Tree.makeRoot()
        defer { Tree.cleanUp(home) }
        try Tree.write(home + "/Downloads/old.zip", bytes: 4_000)
        let report = await move([try Self.candidate(home + "/Downloads/old.zip")], home: home)
        defer { Self.restore(report) }

        #expect(report.moved.count == 1)
        guard case .movedToTrash(let trashPath) = report.items.first?.outcome else {
            Issue.record("Not moved: \(String(describing: report.items.first?.outcome))")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: home + "/Downloads/old.zip"))
        #expect(FileManager.default.fileExists(atPath: trashPath), "The item can be put back from the Trash")
        #expect(report.bytesMovedToTrash == 4_096)
    }

    @Test func changedReplacedOrLinkedItemsAreSkipped() async throws {
        let home = try Tree.makeRoot()
        defer { Tree.cleanUp(home) }
        try Tree.write(home + "/Downloads/grew.bin", bytes: 100)
        try Tree.write(home + "/Downloads/replaced.bin", bytes: 100)
        try Tree.write(home + "/Downloads/linked.bin", bytes: 100)
        try Tree.write(home + "/Downloads/target.bin", bytes: 100)
        let grew = try Self.candidate(home + "/Downloads/grew.bin")
        let replaced = try Self.candidate(home + "/Downloads/replaced.bin")
        let linked = try Self.candidate(home + "/Downloads/linked.bin")
        let gone = try Self.candidate(home + "/Downloads/target.bin")

        try Tree.write(home + "/Downloads/grew.bin", bytes: 200)                 // changed size
        try FileManager.default.removeItem(atPath: home + "/Downloads/replaced.bin")
        try Tree.write(home + "/Downloads/replaced.bin", bytes: 100)             // new inode
        try FileManager.default.removeItem(atPath: home + "/Downloads/linked.bin")
        try FileManager.default.createSymbolicLink(atPath: home + "/Downloads/linked.bin", withDestinationPath: home + "/Downloads/target.bin")
        try FileManager.default.removeItem(atPath: home + "/Downloads/target.bin")  // missing

        let report = await move([grew, replaced, linked, gone], home: home)
        defer { Self.restore(report) }
        #expect(report.moved.isEmpty, "Nothing that changed since the preview is touched")
        #expect(report.items.map(\.outcome) == [.skipped(.changed), .skipped(.changed), .skipped(.changed), .skipped(.missing)])
        #expect(FileManager.default.fileExists(atPath: home + "/Downloads/grew.bin"))
    }

    @Test func refusedPathsAreNeverMoved() async throws {
        let home = try Tree.makeRoot()
        defer { Tree.cleanUp(home) }
        try Tree.write(home + "/Documents/keep.txt", bytes: 10)
        try Tree.write(home + "/Library/Preferences/app.plist", bytes: 10)
        let report = await move([
            try Self.candidate(home + "/Documents"),
            try Self.candidate(home + "/Library/Preferences/app.plist"),
        ], home: home)
        defer { Self.restore(report) }
        #expect(report.items.map(\.outcome) == [.skipped(.notAllowed), .skipped(.notAllowed)])
        #expect(FileManager.default.fileExists(atPath: home + "/Documents/keep.txt"))
    }

    @Test func partialFailuresAreReportedTruthfully() async throws {
        let home = try Tree.makeRoot()
        defer {
            _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: home + "/Downloads/locked")
            Tree.cleanUp(home)
        }
        try Tree.write(home + "/Downloads/ok.bin", bytes: 10)
        try Tree.write(home + "/Downloads/locked/inner.bin", bytes: 10)
        let ok = try Self.candidate(home + "/Downloads/ok.bin")
        let inner = try Self.candidate(home + "/Downloads/locked/inner.bin")
        // A read-only, non-searchable parent: the item can't be moved out of it.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: home + "/Downloads/locked")

        let report = await move([ok, inner], home: home)
        defer { Self.restore(report) }
        #expect(report.moved.map(\.path) == [home + "/Downloads/ok.bin"])
        let other = try #require(report.items.last)
        #expect(!other.outcome.isMoved, "A refused move is never reported as success")
        #expect(report.bytesMovedToTrash == 4_096)
    }

    @Test func stoppingBeforeStartMovesNothing() async throws {
        let home = try Tree.makeRoot()
        defer { Tree.cleanUp(home) }
        try Tree.write(home + "/Downloads/a.bin", bytes: 10)
        let candidate = try Self.candidate(home + "/Downloads/a.bin")
        let task = Task { await move([candidate], home: home) }
        task.cancel()
        let report = await task.value
        defer { Self.restore(report) }
        #expect(!report.isComplete)
        #expect(report.moved.isEmpty)
        #expect(FileManager.default.fileExists(atPath: home + "/Downloads/a.bin"))
    }

    // MARK: Candidates

    @Test func cachesAreListedPerAppWithReasonsAndAppleCachesLeftAlone() async throws {
        let home = try Tree.makeRoot()
        defer { Tree.cleanUp(home) }
        try Tree.write(home + "/Library/Caches/com.example.editor/blob.bin", bytes: 50_000)
        try Tree.write(home + "/Library/Caches/com.apple.Safari/blob.bin", bytes: 50_000)
        let source = LiveCleanupCandidateSource(homePath: home)
        let list = await source.candidates(for: .appCaches, options: CleanupScanOptions(), policy: Self.policy(home))
        #expect(list.candidates.map(\.name) == ["com.example.editor"])
        #expect(list.candidates.first?.isFolder == true)
        #expect((list.candidates.first?.allocatedBytes ?? 0) >= 50_000)
        #expect(list.candidates.first?.reason.contains("editor") == true)
    }

    @Test func oldDownloadsUseTheAgeLimit() async throws {
        let home = try Tree.makeRoot()
        defer { Tree.cleanUp(home) }
        try Tree.write(home + "/Downloads/old.zip", bytes: 1_000)
        try Tree.write(home + "/Downloads/new.zip", bytes: 1_000)
        let old = Date().addingTimeInterval(-90 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: home + "/Downloads/old.zip")
        let source = LiveCleanupCandidateSource(homePath: home)
        let policy = CleanupSafetyPolicy(homePath: home, pickedFolders: [home + "/Downloads"])
        let list = await source.candidates(
            for: .oldDownloads, options: CleanupScanOptions(folder: home + "/Downloads", minimumAgeDays: 30), policy: policy
        )
        #expect(list.candidates.map(\.name) == ["old.zip"])
    }

    @Test func emptyFoldersSkipLinksAndStandardFolders() async throws {
        let home = try Tree.makeRoot()
        defer { Tree.cleanUp(home) }
        let projects = home + "/Projects"
        try FileManager.default.createDirectory(atPath: projects + "/empty", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: projects + "/nested/also-empty", withIntermediateDirectories: true)
        try Tree.write(projects + "/settings-only/.DS_Store", bytes: 10)
        try Tree.write(projects + "/full/file.txt", bytes: 10)
        try FileManager.default.createSymbolicLink(atPath: projects + "/link", withDestinationPath: home)
        let source = LiveCleanupCandidateSource(homePath: home)
        let policy = CleanupSafetyPolicy(homePath: home, pickedFolders: [projects])
        let list = await source.candidates(for: .emptyFolders, options: CleanupScanOptions(folder: projects), policy: policy)
        #expect(Set(list.candidates.map(\.name)) == ["empty", "also-empty", "settings-only"])
    }

    @Test func duplicatesExplainWhichCopyIsKept() async throws {
        let home = try Tree.makeRoot()
        defer { Tree.cleanUp(home) }
        try Tree.write(home + "/a/photo.jpg", bytes: 3_000)
        try Tree.write(home + "/b/photo.jpg", bytes: 3_000)
        let source = LiveCleanupCandidateSource(homePath: home)
        let list = await source.candidates(
            for: .duplicates,
            options: CleanupScanOptions(duplicates: [(path: home + "/b/photo.jpg", keptCopy: home + "/a/photo.jpg")]),
            policy: Self.policy(home)
        )
        #expect(list.candidates.count == 1)
        #expect(list.candidates.first?.reason.contains("photo.jpg") == true)
    }
}

@Suite("JSONLinesCleanupHistoryStore")
struct CleanupHistoryStoreTests {
    @Test func appendsAndReads() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("macpulse-cleanup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = JSONLinesCleanupHistoryStore(directory: directory, now: { now })
        let report = CleanupReport(category: .logs, finishedAt: now, items: [
            CleanupItemResult(path: "/a", allocatedBytes: 1, outcome: .movedToTrash(trashPath: "/t/a")),
        ], isComplete: true)
        try await store.append(report)
        #expect(try await store.reports() == [report])
    }
}
