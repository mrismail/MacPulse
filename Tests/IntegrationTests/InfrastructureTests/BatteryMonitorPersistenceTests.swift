import Foundation
import MacPulseDomain
import Testing
@testable import MacPulseInfrastructure

/// Fixed reading source for end-to-end tests.
private struct FixedSource: BatteryReadingSource {
    let raw: RawBatteryData
    func currentReading(at timestamp: Date) async -> BatteryReading {
        BatteryReadingBuilder.build(from: raw, at: timestamp)
    }
}

/// BatteryMonitor + the real JSON-lines store on disk.
@Suite("BatteryMonitor with on-disk history (integration)")
final class BatteryMonitorPersistenceTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MacPulseE2E-\(UUID().uuidString)", isDirectory: true)

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private static let onBattery = RawBatteryData(
        hasInternalBattery: true, isPresent: true, currentCapacity: 64, maxCapacity: 100,
        isCharging: false, isCharged: false, powerSourceState: "Battery Power",
        timeToEmptyMinutes: 200, batteryHealth: "Good"
    )

    @Test func samplesSurviveARestartAndFeedTheEstimate() async throws {
        let end = Date(timeIntervalSince1970: 1_793_448_000)
        let store = JSONLinesBatteryHistoryStore(directory: directory)

        // A previous session recorded 20 minutes of discharge from 74% to 65%.
        for (index, percentage) in stride(from: 74.0, through: 65.0, by: -1.0).enumerated() {
            try await store.append(BatterySnapshot(
                timestamp: end.addingTimeInterval(Double(index - 10) * 120),
                percentage: percentage, isCharging: false, isPluggedIn: false
            ))
        }

        // "Restart": a new monitor and a new store instance over the same directory.
        let monitor = BatteryMonitor(
            source: FixedSource(raw: Self.onBattery),
            history: JSONLinesBatteryHistoryStore(directory: directory),
            now: { end }
        )
        await monitor.refresh()

        let status = try #require(await monitor.latestStatus)
        #expect(status.runtimeFromRecentDischarge.isAvailable)
        #expect(status.historyIssue == nil)
        let stored = try await monitor.history(since: .distantPast)
        #expect(stored.count == 11)
        #expect(stored.last?.percentage == 64)

        try await monitor.clearHistory()
        #expect(try await monitor.history(since: .distantPast).count == 1)
    }
}
