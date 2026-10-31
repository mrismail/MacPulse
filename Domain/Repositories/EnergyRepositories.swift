import Foundation

/// Reads the current user's processes and system CPU counters.
public protocol ProcessSnapshotSource: Sendable {
    func snapshot(at timestamp: Date) async -> ProcessSnapshot
}

/// Stores hourly app usage on this Mac (for trends).
public protocol AppUsageHistoryRepository: Sendable {
    func append(_ records: [AppUsageRecord]) async throws
    /// Records with `from <= hourStart <= to`, oldest first.
    func records(from: Date, to: Date) async throws -> [AppUsageRecord]
    func prune(olderThan date: Date) async throws
    func deleteAll() async throws
}

/// Persists the user's alert preferences.
public protocol DrainAlertSettingsStore: Sendable {
    func load() -> DrainAlertSettings
    func save(_ settings: DrainAlertSettings)
}

/// Delivers drain alerts as macOS notifications.
public protocol DrainAlertNotifier: Sendable {
    /// Asks for permission if needed. Returns whether notifications may be shown.
    func requestAuthorization() async -> Bool
    func post(_ alert: DrainAlert) async
}

/// Latest app activity, for the Energy screen, the Battery screen and the Overview.
public struct EnergyStatus: Sendable, Equatable {
    public let timestamp: Date
    /// Length of the latest sampling interval, seconds.
    public let intervalSeconds: TimeInterval
    /// Apps during the latest interval, ranked.
    public let current: [AppUsage]
    /// Apps averaged over the recent window (default 10 minutes), ranked.
    public let recent: [AppUsage]
    public let recentWindowMinutes: Int
    /// Whole-system CPU busy, percent of total capacity.
    public let systemCPUPercent: Metric<Double>
    /// `true` when macOS reported per-app energy for the latest interval.
    public let energyDataAvailable: Bool
    /// Other users' processes (system daemons) that can't be read without admin rights.
    public let unreadableProcessCount: Int
    /// MacPulse's own CPU use, percent of one core.
    public let ownCPUPercent: Metric<Double>
    public let onBattery: Bool?
    public let alerts: [DrainAlert]
    public let historyIssue: AppError?

    public init(
        timestamp: Date,
        intervalSeconds: TimeInterval,
        current: [AppUsage],
        recent: [AppUsage],
        recentWindowMinutes: Int,
        systemCPUPercent: Metric<Double>,
        energyDataAvailable: Bool,
        unreadableProcessCount: Int,
        ownCPUPercent: Metric<Double>,
        onBattery: Bool?,
        alerts: [DrainAlert],
        historyIssue: AppError? = nil
    ) {
        self.timestamp = timestamp
        self.intervalSeconds = intervalSeconds
        self.current = current
        self.recent = recent
        self.recentWindowMinutes = recentWindowMinutes
        self.systemCPUPercent = systemCPUPercent
        self.energyDataAvailable = energyDataAvailable
        self.unreadableProcessCount = unreadableProcessCount
        self.ownCPUPercent = ownCPUPercent
        self.onBattery = onBattery
        self.alerts = alerts
        self.historyIssue = historyIssue
    }
}

/// App-wide process monitoring service.
public protocol EnergyMonitoring: Sendable {
    /// Starts background sampling. Calling it again has no effect.
    func start() async
    /// Samples more often while a screen showing live activity is visible.
    func setDetailedSampling(_ enabled: Bool) async
    /// The latest status (replayed immediately if known) and every subsequent update.
    func updates() async -> AsyncStream<EnergyStatus>
    /// Hourly usage records since `date`, including the hour in progress.
    func usageHistory(since date: Date) async throws -> [AppUsageRecord]
    func alertSettings() async -> DrainAlertSettings
    /// Saves settings. Returns `false` if notifications were requested but not allowed.
    @discardableResult
    func updateAlertSettings(_ settings: DrainAlertSettings) async -> Bool
    func clearHistory() async throws
}
