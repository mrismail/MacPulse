import Foundation
import MacPulseDomain
import MacPulseShared
import Observation

/// Which figures the Energy table shows.
public enum EnergyTimeframe: String, CaseIterable, Identifiable, Sendable {
    case now
    case recent

    public var id: String { rawValue }
}

/// Range of the per-app trend chart.
public enum EnergyTrendRange: String, CaseIterable, Identifiable, Sendable {
    case day
    case week

    public var id: String { rawValue }

    public var duration: TimeInterval {
        switch self {
        case .day: 24 * 3_600
        case .week: 7 * 24 * 3_600
        }
    }
}

/// One point of an app's hourly trend.
public struct EnergyTrendPoint: Identifiable, Sendable, Equatable {
    public var id: Date { hour }
    public let hour: Date
    /// Average CPU over the observed part of the hour, percent of one core.
    public let averageCPUPercent: Double
    public let onBattery: Bool
}

@MainActor
@Observable
public final class EnergyViewModel {
    public private(set) var status: EnergyStatus?
    public var timeframe: EnergyTimeframe = .recent
    public var selectedAppID: String?
    public var trendRange: EnergyTrendRange = .day
    public private(set) var trend: [EnergyTrendPoint] = []
    public private(set) var historyError: AppError?
    public private(set) var settings = DrainAlertSettings()
    /// Set when the user turned notifications on but macOS didn't allow them.
    public private(set) var notificationsDenied = false

    @ObservationIgnored private var history: [AppUsageRecord] = []
    @ObservationIgnored private let monitor: any EnergyMonitoring
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(monitor: any EnergyMonitoring, now: @escaping @Sendable () -> Date = { Date() }) {
        self.monitor = monitor
        self.now = now
    }

    /// Apps for the selected timeframe, ranked by estimated impact.
    public var apps: [AppUsage] {
        guard let status else { return [] }
        return timeframe == .now ? status.current : status.recent
    }

    /// The top apps while on battery, for the Battery screen.
    public var topApps: [AppUsage] {
        Array((status?.recent ?? []).filter { $0.cpuPercent >= 0.5 || ($0.energyMilliwatts ?? 0) > 0 }.prefix(5))
    }

    public var selectedApp: AppUsage? {
        guard let selectedAppID else { return nil }
        return apps.first { $0.id == selectedAppID } ?? status?.recent.first { $0.id == selectedAppID }
    }

    public var systemCPU: Metric<Double> { status?.systemCPUPercent ?? .unavailable(.notYetSampled) }
    public var ownCPU: Metric<Double> { status?.ownCPUPercent ?? .unavailable(.notYetSampled) }

    /// Follows updates until the calling task is cancelled. `detailed` asks the monitor to
    /// sample faster while a live view is on screen.
    public func observe(detailed: Bool) async {
        if detailed {
            await monitor.setDetailedSampling(true)
        }
        settings = await monitor.alertSettings()
        for await status in await monitor.updates() {
            self.status = status
        }
        if detailed {
            await monitor.setDetailedSampling(false)
        }
    }

    public func loadHistory() async {
        let requested = trendRange
        do {
            let records = try await monitor.usageHistory(since: now().addingTimeInterval(-requested.duration))
            guard requested == trendRange, !Task.isCancelled else { return }
            history = records
            historyError = nil
            rebuildTrend()
        } catch {
            guard requested == trendRange else { return }
            let appError = AppError.wrapping(error, userMessage: String(localized: "Couldn't load app usage history."))
            Log.logger(.energy).log(appError, context: "Usage history")
            historyError = appError
        }
    }

    public func select(_ appID: String?) {
        selectedAppID = appID
        rebuildTrend()
    }

    public func updateSettings(_ newSettings: DrainAlertSettings) async {
        let allowed = await monitor.updateAlertSettings(newSettings)
        notificationsDenied = newSettings.sendsNotifications && !allowed
        settings = await monitor.alertSettings()
    }

    private func rebuildTrend() {
        guard let selectedAppID else {
            trend = []
            return
        }
        trend = history
            .filter { $0.appKey == selectedAppID }
            .map { EnergyTrendPoint(hour: $0.hourStart, averageCPUPercent: $0.averageCPUPercent, onBattery: $0.onBatterySeconds > $0.sampledSeconds / 2) }
    }
}
