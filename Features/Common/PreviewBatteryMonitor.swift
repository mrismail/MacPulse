import Foundation
import MacPulseDomain

/// Deterministic battery data for SwiftUI previews and UI tests: a MacBook on battery
/// at 72% with 24 hours of history that includes one overnight charging session.
public struct PreviewBatteryMonitor: BatteryMonitoring {
    private let referenceDate: Date

    public init(referenceDate: Date = Date()) {
        self.referenceDate = referenceDate
    }

    public static let sampleRaw = RawBatteryData(
        hasInternalBattery: true,
        isPresent: true,
        currentCapacity: 72,
        maxCapacity: 100,
        isCharging: false,
        isCharged: false,
        powerSourceState: "Battery Power",
        timeToEmptyMinutes: 312,
        timeToFullMinutes: -1,
        batteryHealth: "Good",
        registry: .init(
            cycleCount: 241,
            designCapacity: 8_790,
            appleRawMaxCapacity: 7_912,
            temperatureCentiCelsius: 3_105,
            voltageMillivolts: 12_480,
            amperageMilliamps: -1_150
        )
    )

    public func status() -> BatteryStatus {
        let reading = BatteryReadingBuilder.build(from: Self.sampleRaw, at: referenceDate)
        let basis = "Based on your discharge rate over the last 30 minutes."
        return BatteryStatus(
            reading: reading,
            runtimeFromRecentDischarge: .estimated(295, basis: basis),
            dischargeRatePercentPerHour: .estimated(14.6, basis: basis)
        )
    }

    public func sampleHistory() -> [BatterySnapshot] {
        // Every 10 minutes for 24 h: on battery, plugged in from 20 h to 14 h ago, then on battery again.
        (0...144).map { step in
            let minutesAgo = Double(144 - step) * 10
            let timestamp = referenceDate.addingTimeInterval(-minutesAgo * 60)
            let hoursAgo = minutesAgo / 60
            let pluggedIn = hoursAgo > 14 && hoursAgo <= 20
            let percentage: Double
            if hoursAgo > 20 {
                percentage = 60 - (24 - hoursAgo) * 8  // 60 → 28
            } else if pluggedIn {
                percentage = min(100, 28 + (20 - hoursAgo) * 20)  // 28 → 100
            } else {
                percentage = max(5, 100 - (14 - hoursAgo) * 2)  // 100 → 72
            }
            return BatterySnapshot(
                timestamp: timestamp,
                percentage: percentage.rounded(),
                isCharging: pluggedIn && percentage < 100,
                isPluggedIn: pluggedIn,
                healthPercentage: 90,
                cycleCount: 241
            )
        }
    }

    public func start() async {}
    public func refresh() async {}

    public func updates() async -> AsyncStream<BatteryStatus> {
        let status = status()
        return AsyncStream { continuation in
            continuation.yield(status)
            continuation.finish()
        }
    }

    public func history(since date: Date) async throws -> [BatterySnapshot] {
        sampleHistory().filter { $0.timestamp >= date }
    }

    public func clearHistory() async throws {}
}
