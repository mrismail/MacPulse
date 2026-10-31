import Darwin
import Foundation
import MacPulseDomain
import Testing
@testable import MacPulseInfrastructure

/// Runs against the real machine (CI runner or developer Mac).
@Suite("LiveProcessSnapshotSource (integration)")
struct LiveProcessSnapshotSourceTests {
    @Test func readsOwnProcessAndSystemCPU() async throws {
        let source = LiveProcessSnapshotSource()
        let snapshot = await source.snapshot(at: Date())
        #expect(snapshot.ownPID == getpid())
        #expect(snapshot.processes.count > 1)
        #expect(snapshot.systemCPU != nil)
        #expect(snapshot.logicalCPUCount > 0)
        let own = try #require(snapshot.processes.first { $0.identity.pid == getpid() })
        #expect(own.cpuTimeNanoseconds > 0)
        #expect((own.residentBytes ?? 0) > 0)
        #expect(own.footprintBytes != nil)  // proc_pid_rusage works without the sandbox
        #expect(!own.name.isEmpty)
    }

    @Test func cpuTimeGrowsWithWork() async throws {
        let source = LiveProcessSnapshotSource()
        let before = await source.snapshot(at: Date())
        // Burn ~100 ms of CPU.
        let deadline = Date().addingTimeInterval(0.1)
        var counter = 0.0
        while Date() < deadline { counter += sin(counter) + 1 }
        #expect(counter > 0)
        let after = await source.snapshot(at: Date())

        let activity = ProcessActivityCalculator.activity(from: before, to: after)
        let own = try #require(activity.first { $0.identity.pid == getpid() })
        #expect(own.cpuPercent > 10)
        #expect(own.cpuPercent < 100 * Double(ProcessInfo.processInfo.activeProcessorCount) + 1)
    }

    @Test func onlyCurrentUsersProcessesAreRead() async {
        let snapshot = await LiveProcessSnapshotSource().snapshot(at: Date())
        let table = ProcessTable.entries()
        let mine = Set(table.filter { $0.uid == getuid() }.map(\.pid))
        #expect(snapshot.processes.allSatisfy { mine.contains($0.identity.pid) })
        #expect(snapshot.unreadableProcessCount > 0)  // root daemons exist on every Mac
    }

    @Test func snapshotIsFastEnough() async {
        let source = LiveProcessSnapshotSource()
        _ = await source.snapshot(at: Date())  // warm the path cache, like the monitor does
        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0..<5 {
            _ = await source.snapshot(at: Date())
        }
        let average = (clock.now - start) / 5
        #expect(average < .milliseconds(100), "Average snapshot took \(average)")
    }

    @Test func machTimebaseConversion() {
        #expect(MachTimebase(numerator: 1, denominator: 1).nanoseconds(fromTicks: 1_000) == 1_000)
        // Apple silicon: 125/3 ns per tick.
        #expect(MachTimebase(numerator: 125, denominator: 3).nanoseconds(fromTicks: 24_000_000) == 1_000_000_000)
        #expect(MachTimebase.current.nanoseconds(fromTicks: 0) == 0)
    }

    @Test func processTableHasStartTimes() {
        let me = ProcessTable.entries().first { $0.pid == getpid() }
        #expect(me != nil)
        #expect((me?.startTimeMicroseconds ?? 0) > 1_600_000_000_000_000)  // after 2020
    }
}

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
        try await store.append([record(0), record(1, "b"), record(-48)])
        #expect(try await store.records(from: .distantPast, to: .distantFuture).count == 3)
        #expect(try await store.records(from: hour, to: hour.addingTimeInterval(3_600)).map(\.appKey) == ["a", "b"])

        try await store.prune(olderThan: hour.addingTimeInterval(-24 * 3_600))
        #expect(try await store.records(from: .distantPast, to: .distantFuture).count == 2)

        try await store.deleteAll()
        #expect(try await store.records(from: .distantPast, to: .distantFuture).isEmpty)
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
