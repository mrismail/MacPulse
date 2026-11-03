import Foundation
import MacPulseDomain
@testable import MacPulseInfrastructure
import Testing

/// Real files in a temporary folder; the Phase 5 acceptance cases.
@Suite("DuplicateFinder", .serialized)
struct DuplicateFinderTests {
    typealias Tree = FileSystemScannerTests

    static func bytes(_ count: Int, seed: UInt8) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ Int(seed)) })
    }

    static func write(_ path: String, _ data: Data) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    func find(_ roots: [String], minimum: Int64 = 1, categories: Set<FileCategory>? = nil) async -> DuplicateScanResult {
        let policy = ScanPathPolicy(homePath: "/nonexistent-home", approvedRoots: roots)
        return await DuplicateFinder().findDuplicates(
            DuplicateScanRequest(roots: roots, policy: policy, minimumBytes: minimum, categories: categories)
        ) { _ in }
    }

    @Test func identicalFilesInDifferentFoldersAreOneVerifiedGroup() async throws {
        let root = try Tree.makeRoot()
        defer { Tree.cleanUp(root) }
        let content = Self.bytes(300_000, seed: 1)  // > 128 KB: quick hash, full hash and byte check
        try Self.write(root + "/a/photo.jpg", content)
        try Self.write(root + "/b/copy of photo.jpg", content)
        try Self.write(root + "/c/other.jpg", Self.bytes(300_000, seed: 2))

        let result = await find([root])
        #expect(result.isComplete)
        #expect(result.groups.count == 1)
        let group = try #require(result.groups.first)
        #expect(Set(group.files.map(\.path)) == [root + "/a/photo.jpg", root + "/b/copy of photo.jpg"])
        #expect(group.contentHash.count == 64)
        #expect((group.potentialSavings.value ?? 0) >= 300_000)
        #expect(result.statistics.verified == 2)
    }

    @Test func sameNameButDifferentContentIsNeverIdentical() async throws {
        let root = try Tree.makeRoot()
        defer { Tree.cleanUp(root) }
        try Self.write(root + "/one/report.pdf", Self.bytes(10_000, seed: 3))
        try Self.write(root + "/two/report.pdf", Self.bytes(10_000, seed: 4))  // same name, same size

        let result = await find([root])
        #expect(result.groups.isEmpty)
        #expect(result.statistics.sameSizeFiles == 2)
    }

    @Test func sameStartAndEndButDifferentMiddleIsNotIdentical() async throws {
        let root = try Tree.makeRoot()
        defer { Tree.cleanUp(root) }
        var first = Self.bytes(400_000, seed: 5)
        var second = first
        second[200_000] ^= 0xFF  // one byte in the middle
        try Self.write(root + "/x.bin", first)
        try Self.write(root + "/y.bin", second)
        first.removeAll()

        let result = await find([root])
        #expect(result.groups.isEmpty)
        #expect(result.statistics.quickHashed == 2)
        #expect(result.statistics.fullyHashed == 2, "The quick hash matched, so the full hash decided")
    }

    @Test func hardLinksAreNotCopies() async throws {
        let root = try Tree.makeRoot()
        defer { Tree.cleanUp(root) }
        let content = Self.bytes(50_000, seed: 6)
        try Self.write(root + "/only.dat", content)
        try FileManager.default.linkItem(atPath: root + "/only.dat", toPath: root + "/only-link.dat")

        var result = await find([root])
        #expect(result.groups.isEmpty, "A file and its hard link are one stored file")
        #expect(result.statistics.hardLinks == 1)

        try Self.write(root + "/real-copy.dat", content)
        result = await find([root])
        let group = try #require(result.groups.first)
        #expect(group.files.count == 2)
        #expect(group.files.contains { $0.hardLinkPaths.count == 1 })
    }

    @Test func symbolicLinksAndEmptyFilesAreIgnored() async throws {
        let root = try Tree.makeRoot()
        defer { Tree.cleanUp(root) }
        try Self.write(root + "/data.bin", Self.bytes(20_000, seed: 7))
        try FileManager.default.createSymbolicLink(atPath: root + "/data-link.bin", withDestinationPath: root + "/data.bin")
        try Self.write(root + "/empty1", Data())
        try Self.write(root + "/empty2", Data())

        let result = await find([root])
        #expect(result.groups.isEmpty)
        #expect(result.statistics.filesConsidered == 1)
    }

    @Test func smallIdenticalFilesAndLargeGroups() async throws {
        let root = try Tree.makeRoot()
        defer { Tree.cleanUp(root) }
        let content = Self.bytes(1_000, seed: 8)
        for index in 0..<50 {
            try Self.write(root + "/copies/\(index).txt", content)
        }
        let result = await find([root])
        let group = try #require(result.groups.first)
        #expect(group.files.count == 50)
        let perCopy = try #require(group.files.first?.allocatedBytes)
        #expect(group.potentialSavings.value == perCopy * 49)
        #expect(result.extraCopies == 49)
    }

    @Test func unreadableFilesAreExcludedNotGuessed() async throws {
        let root = try Tree.makeRoot()
        defer {
            _ = try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: root + "/locked.dat")
            Tree.cleanUp(root)
        }
        let content = Self.bytes(5_000, seed: 9)
        try Self.write(root + "/open.dat", content)
        try Self.write(root + "/locked.dat", content)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root + "/locked.dat")

        let result = await find([root])
        #expect(result.groups.isEmpty)
        #expect(result.statistics.excluded[.unreadable] == 1)
    }

    @Test func packageContentsAreNotOffered() async throws {
        let root = try Tree.makeRoot()
        defer { Tree.cleanUp(root) }
        let content = Self.bytes(9_000, seed: 10)
        try Self.write(root + "/Tool.app/Contents/Resources/icon.dat", content)
        try Self.write(root + "/icon.dat", content)

        let result = await find([root])
        #expect(result.groups.isEmpty)
    }

    @Test func filtersAndOverlappingRoots() async throws {
        let root = try Tree.makeRoot()
        defer { Tree.cleanUp(root) }
        let small = Self.bytes(2_000, seed: 11)
        let large = Self.bytes(200_000, seed: 12)
        try Self.write(root + "/s1.txt", small)
        try Self.write(root + "/s2.txt", small)
        try Self.write(root + "/sub/l1.mov", large)
        try Self.write(root + "/sub/l2.mov", large)

        let big = await find([root, root + "/sub"], minimum: 100_000)
        #expect(big.groups.count == 1)
        #expect(big.groups.first?.files.count == 2, "Overlapping roots don't list a file twice")

        // Temporary-folder paths are categorized by location, so filter by whatever the
        // large files' category is and by one that matches nothing.
        let largeCategory = FileCategorizer.category(forPath: root + "/sub/l1.mov")
        let matching = await find([root], categories: [largeCategory])
        #expect(matching.groups.contains { $0.category == largeCategory })
        let none = await find([root], categories: [.audio])
        #expect(none.groups.isEmpty)
    }

    @Test func stoppingReturnsAPartialResult() async throws {
        let root = try Tree.makeRoot()
        defer { Tree.cleanUp(root) }
        for index in 0..<200 {
            try Self.write(root + "/f\(index % 20)/\(index).bin", Self.bytes(4_000, seed: UInt8(index % 3)))
        }
        let task = Task { await find([root]) }
        task.cancel()
        let result = await task.value
        #expect(!result.isComplete)
    }
}

@Suite("DuplicateFinder — files changing and placeholders", .serialized)
struct DuplicateChangeTests {
    typealias Tree = FileSystemScannerTests

    @Test func aFileThatChangesDuringTheSearchIsLeftOut() async throws {
        let root = try Tree.makeRoot()
        defer { Tree.cleanUp(root) }
        let content = DuplicateFinderTests.bytes(300_000, seed: 21)
        try DuplicateFinderTests.write(root + "/a.bin", content)
        try DuplicateFinderTests.write(root + "/b.bin", content)
        let changed = root + "/b.bin"
        // Just before b.bin is read, another app rewrites it (same size, new time).
        let finder = DuplicateFinder(beforeReading: { path in
            guard path == changed else { return }
            try? DuplicateFinderTests.bytes(300_000, seed: 22).write(to: URL(fileURLWithPath: path))
        })
        let policy = ScanPathPolicy(homePath: "/nonexistent-home", approvedRoots: [root])
        let result = await finder.findDuplicates(DuplicateScanRequest(roots: [root], policy: policy)) { _ in }
        #expect(result.groups.isEmpty, "A file that changed is never shown as a duplicate")
        #expect(result.statistics.excluded[.changedDuringScan] == 1)
    }

    @Test func datalessFlagIsRecognized() {
        #expect(DuplicateSearch.isDataless(flags: 0x4000_0000))
        #expect(!DuplicateSearch.isDataless(flags: 0x0000_0020))
    }
}
