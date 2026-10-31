import Foundation
import MacPulseDomain
import Testing
@testable import MacPulseInfrastructure

@Suite("JSONLinesBatteryHistoryStore")
struct JSONLinesBatteryHistoryStoreTests {
    private let directory: URL
    private let store: JSONLinesBatteryHistoryStore
    /// 2026-10-31 12:00:00 UTC
    private let noon = Date(timeIntervalSince1970: 1_793_448_000)

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacPulseTests-\(UUID().uuidString)", isDirectory: true)
        store = JSONLinesBatteryHistoryStore(directory: directory)
    }

    private func snapshot(_ offset: TimeInterval, _ percentage: Double = 50) -> BatterySnapshot {
        BatterySnapshot(
            timestamp: noon.addingTimeInterval(offset),
            percentage: percentage,
            isCharging: false,
            isPluggedIn: false,
            cycleCount: 100
        )
    }

    private func files() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    @Test func appendAndReadBack() async throws {
        let first = snapshot(0, 80)
        let second = snapshot(60, 79)
        try await store.append(second)
        try await store.append(first)

        let read = try await store.snapshots(from: .distantPast, to: .distantFuture)
        #expect(read == [first, second])  // sorted by time
    }

    @Test func filesAreSplitByUTCDayAndPrivate() async throws {
        try await store.append(snapshot(0))
        try await store.append(snapshot(24 * 3_600))
        #expect(try files() == ["battery-2026-10-31.jsonl", "battery-2026-11-01.jsonl"])

        let attributes = try FileManager.default.attributesOfItem(
            atPath: directory.appendingPathComponent("battery-2026-10-31.jsonl").path
        )
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue == 0o600)
    }

    @Test func rangeQueriesAreInclusiveAndFiltered() async throws {
        for minute in 0..<10 {
            try await store.append(snapshot(Double(minute) * 60))
        }
        let read = try await store.snapshots(from: noon.addingTimeInterval(120), to: noon.addingTimeInterval(300))
        #expect(read.count == 4)
        #expect(try await store.snapshots(from: noon.addingTimeInterval(10), to: noon).isEmpty)
    }

    @Test func pruneRemovesWholeOldDays() async throws {
        try await store.append(snapshot(-3 * 24 * 3_600))
        try await store.append(snapshot(-1 * 24 * 3_600))
        try await store.append(snapshot(0))

        try await store.prune(olderThan: noon.addingTimeInterval(-2 * 24 * 3_600))

        #expect(try files() == ["battery-2026-10-30.jsonl", "battery-2026-10-31.jsonl"])
        #expect(try await store.snapshots(from: .distantPast, to: .distantFuture).count == 2)
    }

    @Test func deleteAllRemovesOnlyHistoryFiles() async throws {
        try await store.append(snapshot(0))
        let unrelated = directory.appendingPathComponent("notes.txt")
        try Data("keep".utf8).write(to: unrelated)

        try await store.deleteAll()

        #expect(try files() == ["notes.txt"])
        #expect(try await store.snapshots(from: .distantPast, to: .distantFuture).isEmpty)
    }

    @Test func corruptLinesAreSkipped() async throws {
        try await store.append(snapshot(0, 70))
        let url = directory.appendingPathComponent("battery-2026-10-31.jsonl")
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{not json}\n\n".utf8))
        try handle.close()
        try await store.append(snapshot(60, 69))

        let read = try await store.snapshots(from: .distantPast, to: .distantFuture)
        #expect(read.map(\.percentage) == [70, 69])
    }

    @Test func missingDirectoryReadsAsEmpty() async throws {
        #expect(try await store.snapshots(from: .distantPast, to: .distantFuture).isEmpty)
        try await store.prune(olderThan: noon)
        try await store.deleteAll()
    }
}
