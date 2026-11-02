import Foundation
import Testing
@testable import MacPulseDomain

@Suite("DuplicateGrouping")
struct DuplicateGroupingTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func candidate(_ path: String, size: Int64, inode: UInt64, modified: TimeInterval = 0, shares: Bool = false) -> DuplicateCandidate {
        DuplicateCandidate(
            path: path, logicalBytes: size, allocatedBytes: size + 96, modified: start.addingTimeInterval(modified),
            category: .other, device: 1, inode: inode, mayShareBlocks: shares
        )
    }

    @Test func hardLinksAreOneStoredFile() {
        let (files, extra) = DuplicateGrouping.collapseHardLinks([
            candidate("/a/x", size: 10, inode: 1),
            candidate("/b/x-link", size: 10, inode: 1),
            candidate("/c/y", size: 10, inode: 2),
        ])
        #expect(files.count == 2)
        #expect(extra == 1)
        #expect(files.first?.otherLinks == ["/b/x-link"])
    }

    @Test func onlySizesWithTwoOrMoreFilesRemain() {
        let (files, _) = DuplicateGrouping.collapseHardLinks([
            candidate("/a", size: 10, inode: 1),
            candidate("/b", size: 10, inode: 2),
            candidate("/c", size: 11, inode: 3),
            candidate("/d", size: 12, inode: 4),
            candidate("/d-link", size: 12, inode: 4),  // a hard link is not a second copy
        ])
        let groups = DuplicateGrouping.sameSize(files)
        #expect(groups.map { $0.map(\.candidate.path) } == [["/a", "/b"]])
    }

    @Test func bucketsSplitByKeyAndSkipMissingKeys() {
        let buckets = DuplicateGrouping.buckets(["a1", "b1", "a2", "c1", "x"]) { item -> Character? in
            item == "x" ? nil : item.first
        }
        #expect(buckets == [["a1", "a2"]])
    }

    @Test func savingsKeepOneCopyAndAreEstimatedWithSharedBlocks() {
        let (files, _) = DuplicateGrouping.collapseHardLinks([
            candidate("/a", size: 1_000, inode: 1, modified: 20),
            candidate("/b", size: 1_000, inode: 2, modified: 10),
            candidate("/c", size: 1_000, inode: 3, modified: 30),
        ])
        let group = DuplicateGrouping.group(hash: "h", files: files)
        #expect(group.files.map(\.path) == ["/b", "/a", "/c"])  // oldest first
        #expect(group.potentialSavings == .measured(2 * 1_096))

        let (cloned, _) = DuplicateGrouping.collapseHardLinks([
            candidate("/a", size: 1_000, inode: 1),
            candidate("/b", size: 1_000, inode: 2, shares: true),
        ])
        let clonedGroup = DuplicateGrouping.group(hash: "k", files: cloned)
        #expect(clonedGroup.potentialSavings.value == 1_096)
        #expect(!clonedGroup.potentialSavings.isMeasured)

        let result = DuplicateScanResult(
            roots: ["/"], startedAt: start, finishedAt: start, isComplete: true,
            groups: DuplicateGrouping.ranked([clonedGroup, group]), statistics: DuplicateScanStatistics(), skipped: []
        )
        #expect(result.groups.first?.contentHash == "h")
        #expect(result.extraCopies == 3)
        #expect(result.potentialSavings.value == 3 * 1_096)
        #expect(!result.potentialSavings.isMeasured)
    }
}

@Suite("DuplicateSelection")
struct DuplicateSelectionTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func group(_ hash: String, _ paths: [String], links: [String: [String]] = [:]) -> DuplicateGroup {
        DuplicateGroup(contentHash: hash, files: paths.enumerated().map { index, path in
            DuplicateFile(
                path: path, hardLinkPaths: links[path] ?? [], logicalBytes: 100, allocatedBytes: 4_096,
                modified: start.addingTimeInterval(Double(index)), category: .images
            )
        })
    }

    @Test func atLeastOneCopyIsAlwaysKept() {
        let g = group("h", ["/a", "/b"])
        var selection = DuplicateSelection()
        selection.toggle(g.files[0], in: g)
        #expect(selection.isMarked(g.files[0]))
        #expect(!selection.canMark(g.files[1], in: g))
        selection.toggle(g.files[1], in: g)
        #expect(!selection.isMarked(g.files[1]), "The last copy can't be marked")
        selection.toggle(g.files[0], in: g)
        #expect(selection.markedPaths.isEmpty)
    }

    @Test func keepNewestOrOldestMarksTheRest() {
        let groups = [group("h", ["/a", "/b", "/c"]), group("k", ["/x", "/y"])]
        var selection = DuplicateSelection()
        selection.markAllExcept(.newest, in: groups)
        #expect(selection.markedPaths == ["/a", "/b", "/x"])
        #expect(selection.savings(in: groups) == 3 * 4_096)
        selection.markAllExcept(.oldest, in: groups)
        #expect(selection.markedPaths == ["/b", "/c", "/y"])
        #expect(selection.markedCount(in: groups) == 3)
        selection.retain(onlyIn: [groups[0]])
        #expect(selection.markedPaths == ["/b", "/c"])
        selection.clear()
        #expect(selection.markedPaths.isEmpty)
    }

    @Test func aCopyWithOtherHardLinksFreesNothing() {
        let g = group("h", ["/a", "/b"], links: ["/a": ["/a-link"]])
        var selection = DuplicateSelection()
        selection.toggle(g.files[0], in: g)
        #expect(selection.savings(in: [g]) == 0)
    }
}
