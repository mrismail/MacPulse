import Foundation
import Testing
@testable import MacPulseDomain

@Suite("ScanSummary and ScanHistory")
struct ScanSummaryTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func summary(_ root: String, bytes: Int64, at offset: TimeInterval, complete: Bool = true) -> ScanSummary {
        ScanSummary(
            rootPath: root, finishedAt: start.addingTimeInterval(offset), durationSeconds: 1, isComplete: complete,
            allocatedBytes: bytes, logicalBytes: bytes, fileCount: 1, recoverableBytes: 0, skippedCount: 0,
            topFolders: [], categories: []
        )
    }

    @Test func summaryKeepsTotalsAndTopFoldersOnly() {
        var builder = ScanTreeBuilder(rootPath: "/r")
        for index in 1...7 {
            builder.add(ScannedFile(path: "/r/f\(index)/x", parentPath: "/r/f\(index)", logicalBytes: Int64(index), allocatedBytes: Int64(index * 10), category: .other))
        }
        builder.add(ScannedFile(path: "/r/cache", parentPath: "/r", logicalBytes: 5, allocatedBytes: 5, category: .caches))
        let result = builder.build(startedAt: start, finishedAt: start.addingTimeInterval(3), isComplete: true)
        let summary = ScanSummary(result: result)
        #expect(summary.topFolders.map(\.name) == ["f7", "f6", "f5", "f4", "f3"])
        #expect(summary.allocatedBytes == 285)
        #expect(summary.recoverableBytes == 5)
        #expect(summary.durationSeconds == 3)
        #expect(summary.rootName == "r")
    }

    @Test func changeComparesWithThePreviousCompleteScanOfTheSameFolder() {
        let history = [
            summary("/a", bytes: 100, at: 0),
            summary("/a", bytes: 999, at: 10, complete: false),
            summary("/b", bytes: 50, at: 20),
            summary("/a", bytes: 130, at: 30),
        ]
        #expect(ScanHistory.change(for: history[3], in: history) == 30)
        #expect(ScanHistory.change(for: history[0], in: history) == nil)
        #expect(ScanHistory.change(for: history[1], in: history) == nil)  // stopped scans aren't compared
        #expect(ScanHistory.recent(history, limit: 2).map(\.allocatedBytes) == [130, 50])
    }

    @Test func summariesRoundTripAsJSON() throws {
        let original = summary("/a", bytes: 1, at: 0)
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(ScanSummary.self, from: data) == original)
    }
}
