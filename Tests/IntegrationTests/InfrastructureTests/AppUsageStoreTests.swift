import Foundation
import MacPulseDomain
import Testing
@testable import MacPulseInfrastructure

@Suite("JSONLinesAppUsageStore")
final class JSONLinesAppUsageStoreTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MacPulseUsage-\(UUID().uuidString)", isDirectory: true)
    private let hour = Date(timeIntervalSince1970: 1_793_448_000)  // 2026-10-31 12:00 UTC

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func record(_ hoursFromNoon: Double, _ key: String = "a") -> AppUsageRecord {
        AppUsageRecord(
            hourStart: hour.addingTimeInterval(hoursFromNoon * 3_600), appKey: key, displayName: key,
            cpuSeconds: 60, energyJoules: nil, sampledSeconds: 3_600, onBatterySeconds: 0, peakCPUPercent: 5
        )
    }

    @Test func appendReadPruneAndDelete() async throws {
        let store = JSONLinesAppUsageStore(directory: directory)
        try await store.append([record(0), record(1, "b"), record(-48)])  // three distinct (app, hour)s
        #expect(try await store.records(from: .distantPast, to: .distantFuture).count == 3)
        #expect(try await store.records(from: hour, to: hour.addingTimeInterval(3_600)).map(\.appKey) == ["a", "b"])

        try await store.prune(olderThan: hour.addingTimeInterval(-24 * 3_600))
        #expect(try await store.records(from: .distantPast, to: .distantFuture).count == 2)

        try await store.deleteAll()
        #expect(try await store.records(from: .distantPast, to: .distantFuture).isEmpty)
    }

    @Test func repeatedSavesOfAnHourAreCompacted() async throws {
        let store = JSONLinesAppUsageStore(directory: directory)
        for minutes in [5.0, 10, 15] {
            try await store.append([AppUsageRecord(
                hourStart: hour, appKey: "a", displayName: "a", cpuSeconds: minutes,
                energyJoules: nil, sampledSeconds: minutes * 60, onBatterySeconds: 0, peakCPUPercent: 5
            )])
        }
        let read = try await store.records(from: .distantPast, to: .distantFuture)
        #expect(read.count == 1)
        #expect(read.first?.cpuSeconds == 15)  // the latest cumulative save wins

        try await store.prune(olderThan: hour.addingTimeInterval(-3_600))
        let file = directory.appendingPathComponent("usage-2026-10-31.jsonl")
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 1)
        #expect(try await store.records(from: .distantPast, to: .distantFuture).first?.cpuSeconds == 15)
    }

    @Test func filesAreOwnerOnly() async throws {
        let store = JSONLinesAppUsageStore(directory: directory)
        try await store.append([record(0)])
        let file = directory.appendingPathComponent("usage-2026-10-31.jsonl")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }
}

@Suite("UserDefaultsDrainAlertSettingsStore")
struct UserDefaultsDrainAlertSettingsStoreTests {
    @Test func roundTripsAndDefaults() throws {
        let suite = "MacPulseTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsDrainAlertSettingsStore(defaults: defaults)
        #expect(store.load() == DrainAlertSettings())
        let custom = DrainAlertSettings(isEnabled: false, cpuThresholdPercent: 80, sustainedMinutes: 20, onlyOnBattery: false, sendsNotifications: true)
        store.save(custom)
        #expect(store.load() == custom)
    }
}
