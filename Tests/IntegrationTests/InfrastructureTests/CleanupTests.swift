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

    @Test func putBackRestoresOnlyIntoAFreePlace() async throws {
        let home = try Tree.makeRoot()
        defer { Tree.cleanUp(home) }
        try Tree.write(home + "/Downloads/keep-me.txt", bytes: 100)
        let report = await move([try Self.candidate(home + "/Downloads/keep-me.txt")], home: home)
        guard case .movedToTrash(let trashPath) = report.items.first?.outcome else {
            Issue.record("Not moved")
            return
        }
        let service = FileManagerTrashService()
        // Something new took the name: refuse instead of overwriting it.
        try Tree.write(home + "/Downloads/keep-me.txt", bytes: 5)
        let expected = report.items.first?.identity
        #expect(expected != nil, "The moved item's identity is recorded for Put Back")
        let blocked = await service.putBack(trashPath: trashPath, to: home + "/Downloads/keep-me.txt", expected: expected, policy: Self.policy(home))
        #expect(blocked == .originalPlaceTaken)
        try FileManager.default.removeItem(atPath: home + "/Downloads/keep-me.txt")

        // A different item at the Trash path is never restored.
        let wrong = FileIdentity(device: expected?.device ?? 0, inode: (expected?.inode ?? 0) + 1, size: 0, modifiedSeconds: 0, modifiedNanoseconds: 0, isFolder: false)
        let different = await service.putBack(trashPath: trashPath, to: home + "/Downloads/keep-me.txt", expected: wrong, policy: Self.policy(home))
        #expect(different == .differentItem)

        let restored = await service.putBack(trashPath: trashPath, to: home + "/Downloads/keep-me.txt", expected: expected, policy: Self.policy(home))
        #expect(restored == nil)
        #expect(FileManager.default.fileExists(atPath: home + "/Downloads/keep-me.txt"))
        let again = await service.putBack(trashPath: trashPath, to: home + "/Downloads/keep-me.txt", expected: expected, policy: Self.policy(home))
        #expect(again == .notInTrash)
        // Never into a protected place, and never from outside a Trash folder.
        let elsewhere = await service.putBack(trashPath: home + "/Downloads/keep-me.txt", to: home + "/Library/Preferences/x", expected: nil, policy: Self.policy(home))
        #expect(elsewhere == .notInTrash)
    }

    @Test func putBackNeedsTheRecordedIdentityAndThisUsersTrash() async throws {
        let home = try Tree.makeRoot()
        defer { Tree.cleanUp(home) }
        try Tree.write(home + "/Downloads/old-history.txt", bytes: 10)
        let report = await move([try Self.candidate(home + "/Downloads/old-history.txt")], home: home)
        defer { Self.restore(report) }
        guard case .movedToTrash(let trashPath) = report.items.first?.outcome else {
            Issue.record("Not moved")
            return
        }
        let unknown = await FileManagerTrashService().putBack(trashPath: trashPath, to: home + "/Downloads/old-history.txt", expected: nil, policy: Self.policy(home))
        #expect(unknown == .notVerifiable, "History without an identity can't prove which item it was")
        #expect(FileManagerTrashService.isInTrashFolder("/Volumes/Drive/.Trashes/\(getuid())/a", homePath: home))
        #expect(!FileManagerTrashService.isInTrashFolder("/Volumes/Drive/.Trashes/\(getuid() + 1)/a", homePath: home), "Not another user's Trash")
    }

    @Test func aSwappedItemIsMovedBackOrReportedAsFailed() async throws {
        let home = try Tree.makeRoot()
        defer { Tree.cleanUp(home) }
        try Tree.write(home + "/Downloads/swap.bin", bytes: 100)
        let candidate = try Self.candidate(home + "/Downloads/swap.bin")
        let policy = Self.policy(home)
        let other = FileIdentity(device: candidate.identity.device, inode: candidate.identity.inode + 1, size: 0, modifiedSeconds: 0, modifiedNanoseconds: 0, isFolder: false)

        // What landed isn't the checked item: it goes back where it was.
        let (back, _) = FileManagerTrashService.move(candidate, policy: policy, inspect: { _ in .item(other) })
        #expect(back == .skipped(.changed))
        #expect(FileManager.default.fileExists(atPath: home + "/Downloads/swap.bin"), "Moved back")

        // If its place was taken meanwhile, it can't go back: that is a failure, not a skip.
        let again = try Self.candidate(home + "/Downloads/swap.bin")
        var trashed: String?
        let (failed, _) = FileManagerTrashService.move(
            again, policy: policy,
            afterMove: { trash in
                trashed = trash
                try? Tree.write(home + "/Downloads/swap.bin", bytes: 1)
            },
            inspect: { _ in .item(other) }
        )
        if let trashed { try? FileManager.default.removeItem(atPath: trashed) }
        guard case .failed(let message) = failed else {
            Issue.record("Expected a failure, got \(failed)")
            return
        }
        #expect(message.contains("swap"), "The message says where it is in the Trash")
    }

    @Test func withoutTrashAccessAMoveStillCounts() async throws {
        let home = try Tree.makeRoot()
        defer { Tree.cleanUp(home) }
        try Tree.write(home + "/Downloads/private.bin", bytes: 100)
        let candidate = try Self.candidate(home + "/Downloads/private.bin")
        let (outcome, identity) = FileManagerTrashService.move(candidate, policy: Self.policy(home), inspect: { _ in .noAccess })
        guard case .movedToTrash(let trashPath) = outcome else {
            Issue.record("Expected moved, got \(outcome)")
            return
        }
        defer { try? FileManager.default.moveItem(atPath: trashPath, toPath: home + "/Downloads/private.bin") }
        #expect(identity == candidate.identity, "The identity checked before the move is recorded")
        #expect(!FileManager.default.fileExists(atPath: home + "/Downloads/private.bin"))
    }

    @Test func oldDownloadFoldersAreCheckedAgainBeforeMoving() async throws {
        let home = try Tree.makeRoot()
        defer { Tree.cleanUp(home) }
        let old = Date().addingTimeInterval(-90 * 86_400)
        try Tree.write(home + "/Downloads/Project/a.txt", bytes: 10)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: home + "/Downloads/Project/a.txt")
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: home + "/Downloads/Project")
        let source = LiveCleanupCandidateSource(homePath: home)
        let policy = CleanupSafetyPolicy(homePath: home, pickedFolders: [home + "/Downloads"])
        let list = await source.candidates(
            for: .oldDownloads, options: CleanupScanOptions(folder: home + "/Downloads", minimumAgeDays: 30), policy: policy
        )
        let folder = try #require(list.candidates.first { $0.name == "Project" }, "An old folder is offered")
        // A file saved into it after the review keeps it out of the Trash.
        try Tree.write(home + "/Downloads/Project/new.txt", bytes: 10)
        let (outcome, _) = FileManagerTrashService.move(folder, policy: policy)
        #expect(outcome == .skipped(.changed))
        #expect(FileManager.default.fileExists(atPath: home + "/Downloads/Project/new.txt"))

        // Too many items to check is never "old".
        #expect(FolderAge.of(home + "/Downloads", cutoff: Date(), itemLimit: 1) == .unknown)
    }

    static func marked(_ path: String, kept: String) throws -> MarkedDuplicate {
        MarkedDuplicate(
            path: path, identity: try #require(FileManagerTrashService.identity(atPath: path)),
            keptPath: kept, keptIdentity: try #require(FileManagerTrashService.identity(atPath: kept))
        )
    }

    @Test func aDuplicateIsKeptWhenTheKeptCopyChangedOrVanished() async throws {
        let home = try Tree.makeRoot()
        defer { Tree.cleanUp(home) }
        try Tree.write(home + "/a/photo.jpg", bytes: 3_000)
        try Tree.write(home + "/b/photo.jpg", bytes: 3_000)
        try Tree.write(home + "/c/photo.jpg", bytes: 3_000)
        try Tree.write(home + "/d/photo.jpg", bytes: 3_000)
        let source = LiveCleanupCandidateSource(homePath: home)
        let list = await source.candidates(
            for: .duplicates,
            options: CleanupScanOptions(duplicates: [
                try Self.marked(home + "/b/photo.jpg", kept: home + "/a/photo.jpg"),
                try Self.marked(home + "/d/photo.jpg", kept: home + "/c/photo.jpg"),
            ]),
            policy: Self.policy(home)
        )
        #expect(list.candidates.count == 2)
        // After the preview, one kept copy is edited and the other is deleted.
        try Tree.write(home + "/a/photo.jpg", bytes: 3_500)
        try FileManager.default.removeItem(atPath: home + "/c/photo.jpg")

        let report = await FileManagerTrashService().moveToTrash(list.candidates, category: .duplicates, policy: Self.policy(home)) { _ in }
        defer { Self.restore(report) }
        #expect(report.moved.isEmpty, "The last copy is never moved")
        #expect(report.items.map(\.outcome) == [.skipped(.keptCopyChanged), .skipped(.keptCopyChanged)])
        #expect(FileManager.default.fileExists(atPath: home + "/d/photo.jpg"))
    }

    @Test func aDuplicateEditedAfterTheComparisonIsNotOffered() async throws {
        let home = try Tree.makeRoot()
        defer { Tree.cleanUp(home) }
        try Tree.write(home + "/a/photo.jpg", bytes: 3_000)
        try Tree.write(home + "/b/photo.jpg", bytes: 3_000)
        let marked = try Self.marked(home + "/b/photo.jpg", kept: home + "/a/photo.jpg")
        try Tree.write(home + "/b/photo.jpg", bytes: 3_100)  // edited since the comparison
        let list = await LiveCleanupCandidateSource(homePath: home).candidates(
            for: .duplicates, options: CleanupScanOptions(duplicates: [marked]), policy: Self.policy(home)
        )
        #expect(list.candidates.isEmpty)
    }

    @Test func aFolderThatGotContentIsNotMovedAsEmpty() async throws {
        let home = try Tree.makeRoot()
        defer { Tree.cleanUp(home) }
        let projects = home + "/Projects"
        try FileManager.default.createDirectory(atPath: projects + "/empty", withIntermediateDirectories: true)
        let policy = CleanupSafetyPolicy(homePath: home, pickedFolders: [projects])
        let list = await LiveCleanupCandidateSource(homePath: home).candidates(
            for: .emptyFolders, options: CleanupScanOptions(folder: projects), policy: policy
        )
        let empty = try #require(list.candidates.first)
        #expect(empty.requirement == .stillEmpty)
        try Tree.write(projects + "/empty/new-work.txt", bytes: 10)  // saved after the preview

        let report = await FileManagerTrashService().moveToTrash([empty], category: .emptyFolders, policy: policy) { _ in }
        defer { Self.restore(report) }
        #expect(report.items.first?.outcome == .skipped(.notEmpty))
        #expect(FileManager.default.fileExists(atPath: projects + "/empty/new-work.txt"))
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
            options: CleanupScanOptions(duplicates: [try Self.marked(home + "/b/photo.jpg", kept: home + "/a/photo.jpg")]),
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

    @Test func replacesARunningReportWithAFractionalTime() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("macpulse-cleanup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONLinesCleanupHistoryStore(directory: directory)
        // Date() has sub-second precision; the id must survive the JSON round trip.
        let started = Date()
        let running = CleanupReport(category: .appCaches, finishedAt: started, items: [], isComplete: false)
        try await store.append(running)
        let item = CleanupItemResult(path: "/a", allocatedBytes: 1, outcome: .movedToTrash(trashPath: "/t/a"))
        let done = CleanupReport(category: .appCaches, finishedAt: started, items: [item], isComplete: true)
        try await store.replace(done)
        #expect(try await store.reports() == [done], "The final report replaces the running one")

        let missing = CleanupReport(category: .logs, finishedAt: started, items: [], isComplete: true)
        await #expect(throws: CleanupHistoryError.reportNotFound) { try await store.replace(missing) }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".tmp") }
        #expect(leftovers.isEmpty)
    }
}
