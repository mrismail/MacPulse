import Foundation
import MacPulseDomain
@testable import MacPulseInfrastructure
import Testing

@Suite("JSONLinesScanHistoryStore")
struct ScanHistoryStoreTests {
    func summary(_ root: String, at date: Date) -> ScanSummary {
        ScanSummary(
            rootPath: root, finishedAt: date, durationSeconds: 2, isComplete: true, allocatedBytes: 10,
            logicalBytes: 8, fileCount: 3, recoverableBytes: 1, skippedCount: 0,
            topFolders: [NamedSize(key: root + "/a", name: "a", allocatedBytes: 9)], categories: []
        )
    }

    @Test func appendsReadsAndPrunesOldDays() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("macpulse-scans-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = JSONLinesScanHistoryStore(directory: directory, now: { now })

        try await store.append(summary("/old", at: now.addingTimeInterval(-200 * 86_400)))
        try await store.append(summary("/new", at: now))
        let stored = try await store.summaries()
        #expect(stored.map(\.rootPath) == ["/new"])  // older than 180 days is removed
        #expect(stored.first == summary("/new", at: now))

        try await store.deleteAll()
        #expect(try await store.summaries().isEmpty)
    }

    @Test func exclusionsPersistInUserDefaults() throws {
        let suite = "macpulse-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsScanSettingsStore(defaults: defaults)
        #expect(store.loadExclusions().isEmpty)
        store.saveExclusions(["/Users/t/Movies"])
        #expect(UserDefaultsScanSettingsStore(defaults: defaults).loadExclusions() == ["/Users/t/Movies"])
    }
}
