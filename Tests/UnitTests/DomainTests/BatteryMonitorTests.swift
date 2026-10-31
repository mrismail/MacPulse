import Foundation
import Testing
@testable import MacPulseDomain

// MARK: - Test doubles

/// Returns readings built from a mutable raw fixture.
final class FakeBatterySource: BatteryReadingSource, @unchecked Sendable {
    private let lock = NSLock()
    private var raw: RawBatteryData
    private var _reads = 0

    init(_ raw: RawBatteryData) {
        self.raw = raw
    }

    func set(_ raw: RawBatteryData) {
        lock.withLock { self.raw = raw }
    }

    var reads: Int { lock.withLock { _reads } }

    func currentReading(at timestamp: Date) async -> BatteryReading {
        let raw = lock.withLock {
            _reads += 1
            return self.raw
        }
        return BatteryReadingBuilder.build(from: raw, at: timestamp)
    }
}

/// A clock the test advances by hand.
final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = BatteryFixtures.date) {
        current = start
    }

    var now: Date { lock.withLock { current } }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

/// Power events the test triggers by hand.
final class ManualPowerEvents: PowerSourceEventSource, @unchecked Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: Void.self)
    }

    func events() -> AsyncStream<Void> { stream }

    func fire() { continuation.yield() }
}

/// Polls `condition` for up to ~2 seconds.
func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
    for _ in 0..<200 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}

// MARK: - Tests

@Suite("BatteryMonitor")
struct BatteryMonitorTests {
    private func makeMonitor(
        raw: RawBatteryData = BatteryFixtures.intelOnBattery,
        history: InMemoryBatteryHistoryRepository = InMemoryBatteryHistoryRepository(),
        clock: ManualClock = ManualClock(),
        events: ManualPowerEvents? = nil,
        sleep: @escaping BatteryMonitor.Sleeper = { try await Task.sleep(for: .seconds(3_600)) }
    ) -> (BatteryMonitor, FakeBatterySource) {
        let source = FakeBatterySource(raw)
        let monitor = BatteryMonitor(
            source: source,
            history: history,
            powerEvents: events,
            sleep: sleep,
            now: { clock.now }
        )
        return (monitor, source)
    }

    @Test func refreshRecordsHistoryAndPublishes() async throws {
        let history = InMemoryBatteryHistoryRepository()
        let (monitor, _) = makeMonitor(history: history)

        await monitor.refresh()

        #expect(await history.count == 1)
        let status = try #require(await monitor.latestStatus)
        #expect(status.reading.charge == .measured(64))
        let stored = try await monitor.history(since: .distantPast)
        #expect(stored.first?.percentage == 64)
    }

    @Test func updatesReplayTheLatestStatus() async throws {
        let (monitor, _) = makeMonitor()
        await monitor.refresh()
        var iterator = await monitor.updates().makeAsyncIterator()
        let first = try #require(await iterator.next())
        let latest = await monitor.latestStatus
        #expect(first == latest)
    }

    @Test func subscribersReceiveNewSamples() async throws {
        let (monitor, source) = makeMonitor()
        var iterator = await monitor.updates().makeAsyncIterator()
        var raw = BatteryFixtures.intelOnBattery
        raw.currentCapacity = 63
        source.set(raw)
        await monitor.refresh()
        let next = try #require(await iterator.next())
        #expect(next.reading.charge == .measured(63))
    }

    @Test func runtimeIsEstimatedFromRecordedHistory() async throws {
        let clock = ManualClock()
        // 20 minutes of history falling from 74% to 65%, last sample 2 minutes ago.
        let recorded = series(
            stride(from: 74.0, through: 65.0, by: -1.0).map { $0 },
            interval: 120,
            end: clock.now.addingTimeInterval(-120)
        )
        let history = InMemoryBatteryHistoryRepository(recorded)
        let (monitor, _) = makeMonitor(history: history, clock: clock)  // current reading: 64%

        await monitor.refresh()

        let status = try #require(await monitor.latestStatus)
        let runtime = try #require(status.runtimeFromRecentDischarge.value)
        // 0.5 %/min → 64% ≈ 128 minutes.
        #expect(abs(runtime - 128) <= 2)
        #expect(status.bestRuntimeEstimate == status.runtimeFromRecentDischarge)
        #expect(status.dischargeRatePercentPerHour.isAvailable)
    }

    @Test func withoutHistoryTheMacOSEstimateIsUsed() async throws {
        let (monitor, _) = makeMonitor()
        await monitor.refresh()
        let status = try #require(await monitor.latestStatus)
        #expect(status.runtimeFromRecentDischarge.provenance == .unavailable(.notYetSampled))
        #expect(status.bestRuntimeEstimate.value == 248)
    }

    @Test func onExternalPowerRuntimeIsNotApplicable() async throws {
        let (monitor, _) = makeMonitor(raw: BatteryFixtures.appleSiliconCharging)
        await monitor.refresh()
        let status = try #require(await monitor.latestStatus)
        #expect(status.runtimeFromRecentDischarge.provenance == .unavailable(.notApplicable("Connected to power.")))
    }

    @Test func desktopMacRecordsNothing() async throws {
        let history = InMemoryBatteryHistoryRepository()
        let (monitor, _) = makeMonitor(raw: BatteryFixtures.desktop, history: history)
        await monitor.refresh()
        let status = try #require(await monitor.latestStatus)
        #expect(!status.reading.hasBattery)
        #expect(status.runtimeFromRecentDischarge.provenance == .unavailable(.notSupportedOnThisMac))
        #expect(await history.count == 0)
    }

    @Test func clearHistoryRemovesSamplesAndResamples() async throws {
        let history = InMemoryBatteryHistoryRepository(series([90, 89, 88]))
        let (monitor, _) = makeMonitor(history: history)
        try await monitor.clearHistory()
        #expect(await history.count == 1)
    }

    @Test func startPrunesOldHistoryAndSamplesPeriodically() async {
        let clock = ManualClock()
        let old = BatterySnapshot(
            timestamp: clock.now.addingTimeInterval(-40 * 24 * 3_600),
            percentage: 50, isCharging: false, isPluggedIn: false
        )
        let history = InMemoryBatteryHistoryRepository([old])
        let sleeps = ManualClock(Date(timeIntervalSince1970: 0))  // used as a counter
        let (monitor, source) = makeMonitor(history: history, clock: clock) { _ in
            sleeps.advance(by: 1)
            if sleeps.now.timeIntervalSince1970 >= 3 {
                throw CancellationError()
            }
        }

        await monitor.start()

        #expect(await eventually { source.reads == 3 })
        let snapshots = await history.snapshots(from: .distantPast, to: .distantFuture)
        #expect(!snapshots.contains { $0.id == old.id })
        #expect(snapshots.count == 3)
        await monitor.stop()
    }

    @Test func startTwiceDoesNotDoubleSample() async {
        let (monitor, source) = makeMonitor()
        await monitor.start()
        await monitor.start()
        #expect(await eventually { source.reads >= 1 })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(source.reads == 1)
        await monitor.stop()
    }

    @Test func powerEventsTriggerDebouncedSamples() async {
        let clock = ManualClock()
        let events = ManualPowerEvents()
        let (monitor, source) = makeMonitor(clock: clock, events: events)

        await monitor.start()
        #expect(await eventually { source.reads == 1 })

        clock.advance(by: 10)
        events.fire()
        #expect(await eventually { source.reads == 2 })

        // Within the debounce interval: ignored.
        clock.advance(by: 1)
        events.fire()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(source.reads == 2)

        await monitor.stop()
    }

    @Test func cancelledSubscriberIsRemoved() async {
        let (monitor, _) = makeMonitor()
        let stream = await monitor.updates()
        #expect(await monitor.subscriberCount == 1)
        let task = Task {
            for await _ in stream {}
        }
        task.cancel()
        #expect(await eventually { await monitor.subscriberCount == 0 })
    }
}
