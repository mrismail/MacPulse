import Foundation
import Testing
@testable import MacPulseDomain

@Suite("ScanTreeBuilder")
struct ScanTreeBuilderTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func file(_ path: String, _ allocated: Int64, logical: Int64? = nil, category: FileCategory = .other, package: Bool = false) -> ScannedFile {
        ScannedFile(
            path: path, parentPath: (path as NSString).deletingLastPathComponent,
            logicalBytes: logical ?? allocated, allocatedBytes: allocated, category: category, isPackage: package
        )
    }

    @Test func foldersSumTheirWholeSubtree() throws {
        var builder = ScanTreeBuilder(rootPath: "/r")
        builder.add(file("/r/a/x.mov", 100, category: .video))
        builder.add(file("/r/a/b/y.mov", 50, logical: 40, category: .video))
        builder.add(file("/r/z.txt", 5, category: .documents))
        let result = builder.build(startedAt: start, finishedAt: start, isComplete: true)

        #expect(result.root.allocatedBytes == 155)
        #expect(result.root.logicalBytes == 145)
        #expect(result.root.fileCount == 3)
        let a = try #require(result.root.node(withID: "/r/a"))
        #expect(a.allocatedBytes == 150)
        #expect(a.children?.first?.id == "/r/a/x.mov")  // biggest first
        #expect(result.root.node(withID: "/r/a/b")?.allocatedBytes == 50)
        #expect(result.largestFiles.map(\.id) == ["/r/a/x.mov", "/r/a/b/y.mov", "/r/z.txt"])
        #expect(result.categories.first == CategoryTotal(category: .video, allocatedBytes: 150, logicalBytes: 140, fileCount: 2))
    }

    @Test func smallFilesAreSummedNotKept() throws {
        var limits = ScanLimits()
        limits.filesPerFolder = 2
        limits.largestFiles = 3
        var builder = ScanTreeBuilder(rootPath: "/r", limits: limits)
        for size in [10, 50, 20, 40, 30] as [Int64] {
            builder.add(file("/r/f\(size)", size))
        }
        let result = builder.build(startedAt: start, finishedAt: start, isComplete: true)
        let children = try #require(result.root.children)
        #expect(children.filter { $0.kind == .file }.map(\.allocatedBytes) == [50, 40])
        let other = try #require(children.first { $0.kind == .otherFiles })
        #expect(other.allocatedBytes == 60)
        #expect(other.fileCount == 3)
        #expect(other.path == nil)
        #expect(result.root.allocatedBytes == 150)  // nothing lost
        #expect(result.largestFiles.map(\.allocatedBytes) == [50, 40, 30])
    }

    @Test func incompleteFoldersMarkTheirAncestors() throws {
        var builder = ScanTreeBuilder(rootPath: "/r")
        builder.markIncomplete("/r/a/locked")
        builder.add(file("/r/b/ok.txt", 1))
        let result = builder.build(startedAt: start, finishedAt: start, isComplete: true)
        #expect(result.root.isIncomplete)
        #expect(result.root.node(withID: "/r/a")?.isIncomplete == true)
        #expect(result.root.node(withID: "/r/b")?.isIncomplete == false)
    }

    @Test func packagesAreOneItem() throws {
        var builder = ScanTreeBuilder(rootPath: "/Applications")
        builder.add(file("/Applications/Big.app", 900, category: .applications, package: true))
        let result = builder.build(startedAt: start, finishedAt: start, isComplete: true)
        #expect(result.root.children?.first?.kind == .package)
        #expect(result.root.children?.first?.children == nil)
    }

    @Test func recoverableIsAnEstimateOfCleanableCategories() {
        var builder = ScanTreeBuilder(rootPath: "/r")
        builder.add(file("/r/Library/Caches/a", 30, category: .caches))
        builder.add(file("/r/.Trash/b", 20, category: .trash))
        builder.add(file("/r/c.mov", 100, category: .video))
        let result = builder.build(startedAt: start, finishedAt: start, isComplete: true)
        #expect(result.recoverableBytes.value == 50)
        #expect(!result.recoverableBytes.isMeasured)
        #expect(result.allocatedBytes.isMeasured)
    }

    @Test func pathsOutsideTheRootStayUnderTheRoot() {
        var builder = ScanTreeBuilder(rootPath: "/r")
        builder.add(file("/elsewhere/x", 7))
        let result = builder.build(startedAt: start, finishedAt: start, isComplete: false)
        #expect(result.root.allocatedBytes == 7)
        #expect(!result.isComplete)
    }
}
