import Foundation
import MacPulseDomain

#if DEBUG
/// Deterministic app activity for SwiftUI previews and UI tests: four apps on battery,
/// one of them using enough CPU for a drain alert, and 24 hours of hourly usage.
public actor PreviewEnergyMonitor: EnergyMonitoring {
    private let referenceDate: Date
    private var settings = DrainAlertSettings()
    private var detailed = false

    public init(referenceDate: Date = Date()) {
        self.referenceDate = referenceDate
    }

    public nonisolated static func sampleApps() -> [AppUsage] {
        func app(_ name: String, cpu: Double, memory: UInt64, impact: BatteryImpactLevel, share: Double, processes: Int) -> AppUsage {
            AppUsage(
                id: "/Applications/\(name).app",
                displayName: name,
                appBundlePath: "/Applications/\(name).app",
                processCount: processes,
                cpuPercent: cpu,
                memoryBytes: memory,
                threadCount: processes * 12,
                energyMilliwatts: nil,
                diskBytesPerSecond: 12_000,
                wakeupsPerSecond: cpu * 3,
                impact: .estimated(impact, basis: AppUsageAggregator.cpuBasis),
                shareOfActivity: share
            )
        }
        return [
            app("Web Browser", cpu: 62, memory: 2_400_000_000, impact: .high, share: 0.58, processes: 14),
            app("Code Editor", cpu: 24, memory: 1_100_000_000, impact: .moderate, share: 0.23, processes: 3),
            app("Chat", cpu: 6, memory: 650_000_000, impact: .low, share: 0.06, processes: 4),
            app("Music", cpu: 2, memory: 210_000_000, impact: .low, share: 0.02, processes: 1),
            background(),
        ]
    }

    /// The "macOS & background" row with two members.
    nonisolated static func background() -> AppUsage {
        func member(_ id: String, name: String, bundle: String?, cpu: Double, share: Double) -> AppUsage {
            AppUsage(
                id: id, displayName: name, appBundlePath: bundle, processCount: 1, cpuPercent: cpu,
                memoryBytes: 90_000_000, threadCount: 6, energyMilliwatts: nil, diskBytesPerSecond: 0,
                wakeupsPerSecond: 2, impact: .estimated(.low, basis: AppUsageAggregator.cpuBasis),
                shareOfActivity: share
            )
        }
        let members = [
            member("/System/Library/CoreServices/Dock.app", name: "Dock", bundle: "/System/Library/CoreServices/Dock.app", cpu: 1, share: 0.01),
            member("process:backupd-helper", name: "backupd-helper", bundle: nil, cpu: 0.5, share: 0.005),
        ]
        return AppUsage(
            id: BackgroundGrouping.groupID, displayName: BackgroundGrouping.groupName, appBundlePath: nil,
            processCount: 2, cpuPercent: 1.5, memoryBytes: 180_000_000, threadCount: 12, energyMilliwatts: nil,
            diskBytesPerSecond: 0, wakeupsPerSecond: 4, impact: .estimated(.low, basis: AppUsageAggregator.cpuBasis),
            shareOfActivity: 0.015, children: members
        )
    }

    public func status() -> EnergyStatus {
        let apps = Self.sampleApps()
        return EnergyStatus(
            timestamp: referenceDate,
            intervalSeconds: 10,
            current: apps,
            recent: apps,
            recentWindowMinutes: 10,
            systemCPUPercent: .measured(23),
            energyDataAvailable: false,
            unreadableProcessCount: 212,
            ownCPUPercent: .measured(0.4),
            onBattery: true,
            alerts: [DrainAlert(
                appKey: apps[0].id,
                displayName: apps[0].displayName,
                averageCPUPercent: 62,
                since: referenceDate.addingTimeInterval(-600),
                minutes: settings.sustainedMinutes
            )]
        )
    }

    public func start() async {}

    public func setDetailedSampling(_ enabled: Bool) {
        detailed = enabled
    }

    public func updates() -> AsyncStream<EnergyStatus> {
        let status = status()
        return AsyncStream { continuation in
            continuation.yield(status)
            continuation.finish()
        }
    }

    public func usageHistory(since date: Date) -> [AppUsageRecord] {
        let calendar = Calendar(identifier: .gregorian)
        let currentHour = calendar.dateInterval(of: .hour, for: referenceDate)?.start ?? referenceDate
        return (0..<24).flatMap { hoursAgo -> [AppUsageRecord] in
            let hour = currentHour.addingTimeInterval(-Double(hoursAgo) * 3_600)
            // History is per app; the group row has none of its own.
            return Self.sampleApps().flatMap(\.flattened).filter { !$0.isGroup }.map { app in
                let wave = 0.5 + 0.5 * sin(Double(hoursAgo) / 3)
                return AppUsageRecord(
                    hourStart: hour,
                    appKey: app.id,
                    displayName: app.displayName,
                    cpuSeconds: app.cpuPercent / 100 * 3_600 * wave,
                    energyJoules: nil,
                    sampledSeconds: 3_600,
                    onBatterySeconds: hoursAgo < 8 ? 3_600 : 0,
                    peakCPUPercent: app.cpuPercent * 1.5
                )
            }
        }
        .filter { $0.hourStart >= date }
        .sorted { $0.hourStart < $1.hourStart }
    }

    public func alertSettings() -> DrainAlertSettings {
        settings
    }

    public func updateAlertSettings(_ settings: DrainAlertSettings) -> Bool {
        self.settings = settings
        return true
    }

    public func clearHistory() {}

    public func flush() {}

    public var isDetailedSampling: Bool { detailed }
}
#endif
