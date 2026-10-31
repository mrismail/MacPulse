import Foundation
import Testing
@testable import MacPulseDomain

// MARK: - Doubles

/// Returns snapshots from a script; repeats the last one when the script runs out.
final class ScriptedSnapshotSource: ProcessSnapshotSource, @unchecked Sendable {
    private let lock = NSLock()
    private var script: [ProcessSnapshot]
    private var index = 0

    init(_ script: [ProcessSnapshot]) {
        self.script = script
    }

    var reads: Int { lock.withLock { index } }

    func snapshot(at timestamp: Date) async -> ProcessSnapshot {
        lock.withLock {
            let snapshot = script[min(index, script.count - 1)]
            index += 1
            return snapshot
        }
    }
}

actor InMemoryUsageHistory: AppUsageHistoryRepository {
    private(set) var stored: [AppUsageRecord] = []
    func append(_ records: [AppUsageRecord]) { stored += records }
    func records(from: Date, to: Date) -> [AppUsageRecord] { stored.filter { $0.hourStart >= from && $0.hourStart <= to } }
    func prune(olderThan date: Date) { stored.removeAll { $0.hourStart < date } }
    func deleteAll() { stored.removeAll() }
}

final class MemorySettingsStore: DrainAlertSettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: DrainAlertSettings
    init(_ value: DrainAlertSettings = DrainAlertSettings()) { self.value = value }
    func load() -> DrainAlertSettings { lock.withLock { value } }
    func save(_ settings: DrainAlertSettings) { lock.withLock { value = settings } }
}

actor RecordingNotifier: DrainAlertNotifier {
    let allow: Bool
    private(set) var posted: [DrainAlert] = []
    private(set) var authorizationRequests = 0
    init(allow: Bool) { self.allow = allow }
    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return allow
    }
    func post(_ alert: DrainAlert) async { posted.append(alert) }
}

// MARK: - Tests

@Suite("ProcessMonitor")
struct ProcessMonitorTests {
    typealias F = ProcessFixtures

    /// Snapshots every `step` seconds; "hog" uses `hogCPU` percent of a core, MacPulse 1%.
    private func script(count: Int, step: TimeInterval = 60, hogCPU: Double = 80) -> [ProcessSnapshot] {
        (0..<count).map { index in
            let t = Double(index) * step
            return F.snapshot(at: t, [
                F.sample(pid: 1, name: "hog", cpuSeconds: t * hogCPU / 100),
                F.sample(pid: 2, name: "calm", cpuSeconds: t * 0.02),
                F.sample(pid: 999, name: "MacPulse", cpuSeconds: t * 0.01),
            ], busy: UInt64(index) * 1_000)
        }
    }

    private func makeMonitor(
        source: ScriptedSnapshotSource,
        history: InMemoryUsageHistory = InMemoryUsageHistory(),
        settings: DrainAlertSettings = DrainAlertSettings(sustainedMinutes: 5),
        notifier: RecordingNotifier? = nil,
        onBattery: Bool? = true,
        clockStep: TimeInterval = 60
    ) -> (ProcessMonitor, ManualClock) {
        let clock = ManualClock(F.start)
        let monitor = ProcessMonitor(
            source: source,
            history: history,
            settingsStore: MemorySettingsStore(settings),
            notifier: notifier,
            powerState: { onBattery },
            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) },
            now: { clock.now }
        )
        return (monitor, clock)
    }

    @Test func firstSampleOnlySetsTheBaseline() async {
        let (monitor, _) = makeMonitor(source: ScriptedSnapshotSource(script(count: 2)))
        let first = await monitor.refresh()
        #expect(first == nil)
        let second = await monitor.refresh()
        #expect(second != nil)
    }

    @Test func statusRanksAppsAndReportsOwnOverhead() async throws {
        let (monitor, clock) = makeMonitor(source: ScriptedSnapshotSource(script(count: 2)))
        await monitor.refresh()
        clock.advance(by: 60)
        let status = try #require(await monitor.refresh())

        #expect(status.current.first?.displayName == "hog")
        #expect(abs((status.current.first?.cpuPercent ?? 0) - 80) < 0.001)
        #expect(!status.current.contains { $0.displayName == "MacPulse" })
        #expect(status.ownCPUPercent.isMeasured)
        #expect(abs((status.ownCPUPercent.value ?? 0) - 1) < 0.001)
        #expect(status.unreadableProcessCount == 3)
        #expect(status.energyDataAvailable == false)
        #expect(status.onBattery == true)
        #expect(status.systemCPUPercent.isAvailable)
    }

    @Test func sustainedUseRaisesAlertAndNotifiesOncePerCooldown() async throws {
        let notifier = RecordingNotifier(allow: true)
        let settings = DrainAlertSettings(sustainedMinutes: 5, sendsNotifications: true)
        let (monitor, clock) = makeMonitor(source: ScriptedSnapshotSource(script(count: 10)), settings: settings, notifier: notifier)
        var last: EnergyStatus?
        for _ in 0..<10 {
            last = await monitor.refresh() ?? last
            clock.advance(by: 60)
        }
        let status = try #require(last)
        #expect(status.alerts.map(\.appKey) == ["process:hog"])
        #expect(await notifier.posted.count == 1)  // repeated alerts within the cooldown are not re-sent
    }

    @Test func noAlertsOnExternalPowerByDefault() async throws {
        let (monitor, clock) = makeMonitor(source: ScriptedSnapshotSource(script(count: 10)), onBattery: false)
        var last: EnergyStatus?
        for _ in 0..<10 {
            last = await monitor.refresh() ?? last
            clock.advance(by: 60)
        }
        #expect(try #require(last).alerts.isEmpty)
    }

    @Test func longGapStartsANewBaseline() async {
        let snapshots = [
            F.snapshot(at: 0, [F.sample(pid: 1, name: "a", cpuSeconds: 0)]),
            F.snapshot(at: 3_600, [F.sample(pid: 1, name: "a", cpuSeconds: 3_000)]),  // slept for an hour
            F.snapshot(at: 3_660, [F.sample(pid: 1, name: "a", cpuSeconds: 3_006)]),
        ]
        let (monitor, clock) = makeMonitor(source: ScriptedSnapshotSource(snapshots))
        await monitor.refresh()
        clock.advance(by: 3_600)
        #expect(await monitor.refresh() == nil)
        clock.advance(by: 60)
        let status = await monitor.refresh()
        #expect(abs((status?.current.first?.cpuPercent ?? 0) - 10) < 0.001)
    }

    @Test func hourlyUsageIsPersistedAndPendingHourIsIncluded() async throws {
        let history = InMemoryUsageHistory()
        let (monitor, clock) = makeMonitor(source: ScriptedSnapshotSource(script(count: 63)), history: history)
        for _ in 0..<63 {
            await monitor.refresh()
            clock.advance(by: 60)
        }
        let stored = await history.stored
        #expect(stored.contains { $0.appKey == "process:hog" })
        let all = try await monitor.usageHistory(since: .distantPast)
        #expect(all.count > stored.count)  // includes the hour in progress
    }

    @Test func enablingNotificationsRespectsPermission() async {
        let denied = RecordingNotifier(allow: false)
        let (monitor, _) = makeMonitor(source: ScriptedSnapshotSource(script(count: 2)), notifier: denied)
        let ok = await monitor.updateAlertSettings(DrainAlertSettings(sendsNotifications: true))
        #expect(!ok)
        #expect(await monitor.alertSettings().sendsNotifications == false)
        #expect(await denied.authorizationRequests == 1)
    }

    @Test func detailedSamplingToggles() async {
        let (monitor, _) = makeMonitor(source: ScriptedSnapshotSource(script(count: 2)))
        await monitor.setDetailedSampling(true)
        #expect(await monitor.isDetailedSampling)
        await monitor.setDetailedSampling(false)
        #expect(await monitor.isDetailedSampling == false)
    }

    @Test func startSamplesInTheBackground() async {
        let source = ScriptedSnapshotSource(script(count: 2))
        let (monitor, _) = makeMonitor(source: source)
        await monitor.start()
        #expect(await eventually { source.reads >= 1 })
        await monitor.stop()
    }

    @Test func clearHistoryEmptiesTheStore() async throws {
        let history = InMemoryUsageHistory()
        await history.append([AppUsageRecord(hourStart: F.start, appKey: "x", displayName: "x", cpuSeconds: 1, energyJoules: nil, sampledSeconds: 60, onBatterySeconds: 0, peakCPUPercent: 2)])
        let (monitor, _) = makeMonitor(source: ScriptedSnapshotSource(script(count: 2)), history: history)
        try await monitor.clearHistory()
        #expect(await history.stored.isEmpty)
    }
}
