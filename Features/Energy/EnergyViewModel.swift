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

/// What the per-app trend chart plots.
public enum EnergyTrendMetric: String, CaseIterable, Identifiable, Sendable {
    case cpu
    case memory

    public var id: String { rawValue }
}

/// One point of an app's hourly trend.
public struct EnergyTrendPoint: Identifiable, Sendable, Equatable {
    public var id: Date { hour }
    public let hour: Date
    /// Average CPU over the observed part of the hour, percent of one core.
    public let averageCPUPercent: Double
    public let averageMemoryBytes: Double?
    public let onBattery: Bool
}

/// Wording and selection shared by the Energy screen, the Battery card and the Overview.
public enum EnergyPresentation {
    /// Apps worth listing as "most active": noticeable CPU or any reported energy.
    public static func topApps(_ apps: [AppUsage], limit: Int) -> [AppUsage] {
        Array(apps.filter { $0.cpuPercent >= 0.5 || ($0.energyMilliwatts ?? 0) > 0 }.prefix(limit))
    }

    /// Column/label title for the impact estimate. Only says "battery" when macOS energy
    /// accounting backs it (spec: battery attribution only with a trustworthy metric).
    public static func impactTitle(energyDataAvailable: Bool) -> String {
        energyDataAvailable ? String(localized: "Battery impact") : String(localized: "Activity (CPU-based)")
    }

    public static func topAppsTitle(energyDataAvailable: Bool) -> String {
        energyDataAvailable ? String(localized: "Apps using the most energy") : String(localized: "Most active apps")
    }

    public static func levelTitle(_ level: BatteryImpactLevel?) -> String {
        switch level {
        case .high: String(localized: "High")
        case .moderate: String(localized: "Moderate")
        case .low: String(localized: "Low")
        case nil: "—"
        }
    }

    /// CPU of one core, e.g. "62% CPU"; small values keep one decimal ("0.4% CPU").
    public static func cpuText(_ percent: Double) -> String {
        let digits = percent < 1 ? 0...1 : 0...0
        let value = (percent / 100).formatted(.percent.precision(.fractionLength(digits)))
        return String(localized: "\(value) CPU")
    }
}

@MainActor
@Observable
public final class EnergyViewModel {
    public private(set) var status: EnergyStatus?
    public var timeframe: EnergyTimeframe = .recent
    public private(set) var selectedAppID: String?
    public var trendRange: EnergyTrendRange = .day
    public var trendMetric: EnergyTrendMetric = .cpu
    public private(set) var trend: [EnergyTrendPoint] = []
    public private(set) var historyError: AppError?
    /// What the user sees and edits; saved to the monitor shortly after the last change.
    public private(set) var settings = DrainAlertSettings()
    /// Set when the user turned notifications on but macOS didn't allow them.
    public private(set) var notificationsDenied = false
    /// Table sort order. The default is the impact ranking (highest first).
    public var sortOrder: [KeyPathComparator<AppUsage>] = [KeyPathComparator(\AppUsage.shareOfActivity, order: .reverse)]

    @ObservationIgnored private var history: [AppUsageRecord] = []
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var loadedHistoryVersion: Int?
    @ObservationIgnored private var loadedHour: Date?
    @ObservationIgnored private let saveDelay: Duration
    @ObservationIgnored private let monitor: any EnergyMonitoring
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(
        monitor: any EnergyMonitoring,
        saveDelay: Duration = .milliseconds(400),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.monitor = monitor
        self.saveDelay = saveDelay
        self.now = now
    }

    public var energyDataAvailable: Bool { status?.energyDataAvailable ?? false }

    /// Apps for the selected timeframe in the selected sort order.
    public var apps: [AppUsage] {
        guard let status else { return [] }
        let ranked = timeframe == .now ? status.current : status.recent
        guard let first = sortOrder.first else { return ranked }
        if first.keyPath == \AppUsage.shareOfActivity {
            // The ranking also weighs impact level; keep it and only honour the direction.
            return first.order == .reverse ? ranked : ranked.reversed()
        }
        return ranked.sorted(using: sortOrder)
    }

    public var topApps: [AppUsage] {
        EnergyPresentation.topApps(status?.recent ?? [], limit: 5)
    }

    /// The selected app in the current timeframe, if it is still in it.
    public var selectedApp: AppUsage? {
        guard let selectedAppID else { return nil }
        return apps.first { $0.id == selectedAppID }
    }

    /// `true` when an app is selected but has no activity in the current timeframe.
    public var selectedAppIsIdle: Bool {
        selectedAppID != nil && selectedApp == nil
    }

    public var systemCPU: Metric<Double> { status?.systemCPUPercent ?? .unavailable(.notYetSampled) }
    public var ownCPU: Metric<Double> { status?.ownCPUPercent ?? .unavailable(.notYetSampled) }
    public var memoryPressure: Metric<MemoryPressureLevel> { status?.memoryPressure ?? .unavailable(.notYetSampled) }

    /// Follows updates until the calling task is cancelled. `detailed` asks the monitor to
    /// sample faster while a live view is visible (reference-counted in the monitor).
    public func observe(detailed: Bool) async {
        if detailed {
            await monitor.setDetailedSampling(true)
        }
        if pendingSave == nil {
            settings = await monitor.alertSettings()
        }
        for await status in await monitor.updates() {
            self.status = status
            let hour = Calendar.current.dateInterval(of: .hour, for: status.timestamp)?.start
            if detailed, loadedHistoryVersion != status.historyVersion || loadedHour != hour {
                // History was cleared elsewhere (e.g. the Settings window) or a new hour began.
                loadedHour = hour
                await loadHistory()
            }
        }
        if detailed {
            await monitor.setDetailedSampling(false)
        }
    }

    public func loadHistory() async {
        let requested = trendRange
        let version = status?.historyVersion
        do {
            let records = try await monitor.usageHistory(since: now().addingTimeInterval(-requested.duration))
            guard requested == trendRange, !Task.isCancelled else { return }
            history = records
            historyError = nil
            loadedHistoryVersion = version
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

    /// Edits alert settings. The view updates at once; the save happens once, shortly
    /// after the last change, so dragging a slider doesn't save on every step.
    public func editSettings(_ change: (inout DrainAlertSettings) -> Void) {
        var updated = settings
        change(&updated)
        guard updated != settings else { return }
        settings = updated
        pendingSave?.cancel()
        let delay = saveDelay
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.commitSettings()
        }
    }

    /// Saves pending edits now (e.g. when a slider drag ends).
    public func commitSettings() async {
        pendingSave?.cancel()
        pendingSave = nil
        let requested = settings
        let allowed = await monitor.updateAlertSettings(requested)
        notificationsDenied = requested.sendsNotifications && !allowed
        // Keep newer local edits; take only what the monitor decided about notifications.
        if pendingSave == nil {
            settings = await monitor.alertSettings()
        } else if !allowed {
            settings.sendsNotifications = false
        }
    }

    /// Kept for callers that replace all settings at once.
    public func updateSettings(_ newSettings: DrainAlertSettings) async {
        settings = newSettings
        await commitSettings()
    }

    private func rebuildTrend() {
        guard let selectedAppID else {
            trend = []
            return
        }
        trend = history
            .filter { $0.appKey == selectedAppID }
            .map {
                EnergyTrendPoint(
                    hour: $0.hourStart,
                    averageCPUPercent: $0.averageCPUPercent,
                    averageMemoryBytes: $0.averageMemoryBytes,
                    onBattery: $0.onBatterySeconds > $0.sampledSeconds / 2
                )
            }
    }

    /// The chart's x-axis covers the whole selected range, ending at the current hour.
    public var trendDomain: ClosedRange<Date> {
        let end = Calendar.current.dateInterval(of: .hour, for: now())?.end ?? now()
        return end.addingTimeInterval(-trendRange.duration)...end
    }
}
