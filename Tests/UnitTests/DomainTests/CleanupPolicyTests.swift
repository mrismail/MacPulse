import Foundation
import Testing
@testable import MacPulseDomain

@Suite("CleanupSafetyPolicy")
struct CleanupSafetyPolicyTests {
    let home = "/Users/test"
    var policy: CleanupSafetyPolicy {
        CleanupSafetyPolicy(homePath: home, pickedFolders: ["/Volumes/Data/Inbox"], appDataPath: home + "/Library/Application Support/MacPulse")
    }

    func allowed(_ path: String) -> Bool { policy.verdict(for: path) == .allowed }

    @Test func cachesAndLogsOfAppsAreAllowed() {
        #expect(allowed(home + "/Library/Caches/com.tinyspeck.slackmacgap"))
        #expect(allowed(home + "/Library/Logs/Zoom"))
        #expect(allowed(home + "/Downloads/installer.dmg"))
        #expect(allowed("/Volumes/Data/Inbox/old.zip"))
    }

    @Test func standardFoldersAndTheirRootsAreRefused() {
        #expect(!allowed(home))
        #expect(!allowed(home + "/Documents"))
        #expect(!allowed(home + "/Downloads"))
        #expect(!allowed(home + "/Library"))
        #expect(!allowed(home + "/Library/Caches"))
        #expect(!allowed("/Volumes/Data/Inbox"))
    }

    @Test func appDataAppleCachesSystemAndPackagesAreRefused() {
        #expect(!allowed(home + "/Library/Application Support/Slack"))
        #expect(!allowed(home + "/Library/Preferences/com.example.plist"))
        #expect(!allowed(home + "/Library/Caches/com.apple.Safari"))
        #expect(!allowed(home + "/Library/Caches/CloudKit/x"))
        #expect(!allowed(home + "/Library/Application Support/MacPulse/History/x.jsonl"))
        #expect(!allowed("/System/Library/Caches/x"))
        #expect(!allowed("/Applications/Xcode.app"))
        #expect(!allowed(home + "/Applications/Tool.app/Contents/Resources/big.bin"))
        #expect(!allowed(home + "/Pictures/Photos Library.photoslibrary"))
        #expect(!allowed("/Volumes/Other/file"))
    }

    @Test func excludedFoldersApplyToCleanupToo() {
        let policy = CleanupSafetyPolicy(homePath: home, excludedFolders: [home + "/Library/Caches/com.example.keep"])
        #expect(policy.verdict(for: home + "/Library/Caches/com.example.keep") != .allowed)
        #expect(policy.verdict(for: home + "/Library/Caches/com.example.keep/x") != .allowed)
        #expect(policy.verdict(for: home + "/Library/Caches/com.example.other") == .allowed)
    }

    @Test func traversalTricksAreNormalizedFirst() {
        #expect(!allowed(home + "/Library/Caches/../Preferences/x.plist"))
        #expect(!allowed(home + "/Downloads/../../other/x"))
    }
}

@Suite("FileIdentity and CleanupReport")
struct CleanupModelTests {
    func identity(inode: UInt64 = 7, size: Int64 = 10, seconds: Int = 100, folder: Bool = false) -> FileIdentity {
        FileIdentity(device: 1, inode: inode, size: size, modifiedSeconds: seconds, modifiedNanoseconds: 0, isFolder: folder)
    }

    @Test func filesMustMatchExactlyFoldersByInode() {
        #expect(identity().matches(identity()))
        #expect(!identity().matches(identity(size: 11)))
        #expect(!identity().matches(identity(seconds: 101)))
        #expect(!identity().matches(identity(inode: 8)))
        #expect(identity(folder: true).matches(identity(size: 0, seconds: 999, folder: true)))
        #expect(!identity(folder: true).matches(identity(inode: 8, folder: true)))
        #expect(!identity(folder: true).matches(identity(folder: false)))
    }

    @Test func reportCountsOnlyWhatWasMoved() {
        let report = CleanupReport(category: .appCaches, finishedAt: Date(), items: [
            CleanupItemResult(path: "/a", allocatedBytes: 100, outcome: .movedToTrash(trashPath: "/u/.Trash/a")),
            CleanupItemResult(path: "/b", allocatedBytes: 50, outcome: .skipped(.changed)),
            CleanupItemResult(path: "/c", allocatedBytes: 25, outcome: .failed(message: "No permission")),
        ], isComplete: true)
        #expect(report.bytesMovedToTrash == 100)
        #expect(report.moved.map(\.path) == ["/a"])
        #expect(report.notMoved.count == 2)
    }

    @Test func reportsRoundTripAsJSON() throws {
        let report = CleanupReport(category: .logs, finishedAt: Date(timeIntervalSince1970: 1_800_000_000), items: [
            CleanupItemResult(path: "/a", allocatedBytes: 1, outcome: .movedToTrash(trashPath: "/t/a")),
            CleanupItemResult(path: "/b", allocatedBytes: 2, outcome: .skipped(.missing)),
        ], isComplete: false)
        let data = try JSONEncoder().encode(report)
        #expect(try JSONDecoder().decode(CleanupReport.self, from: data) == report)
    }
}
