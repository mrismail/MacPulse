import Foundation

/// Samples the current user's processes, computes per-app activity and estimated
/// battery impact, keeps a recent window in memory, persists hourly usage, evaluates
/// drain alerts and broadcasts `EnergyStatus`.
///
/// Energy use: one pass over the user's processes (a few syscalls each) every 60 s in
/// the background, or every 10 s while the Energy screen is visible. MacPulse reports
/// its own CPU use in every status so the overhead is visible (Phase 3 acceptance).
public actor ProcessMonitor: EnergyMonitoring {
    public struct Configuration: Sendable {
        public static let defaultHistoryRetentionDays = 7

        public var backgroundInterval: Duration = .seconds(60)
        public var detailedInterval: Duration = .seconds(10)
        public var recentWindow: TimeInterval = 10 * 60
        /// How much interval history to keep in memory (also bounds alert windows).
        public var inMemoryWindow: TimeInterval = 60 * 60
        public var historyRetention: TimeInterval = TimeInterval(defaultHistoryRetentionDays) * 24 * 60 * 60
        /// Don't notify about the same app again within this time.
        public var notificationCooldown: TimeInterval = 30 * 60
        public var thresholds = AppUsageAggregator.Thresholds()
        public var historyIsPersistent = true

        public init() {}
    }

    public typealias Sleeper = @Sendable (Duration) async throws -> Void
    public typealias Clock = @Sendable () -> Date
    public typealias PowerState = @Sendable () async -> Bool?
    public typealias ErrorReporter = @Sendable (AppError) -> Void

    private let source: any ProcessSnapshotSource
    private let historyStore: any AppUsageHistoryRepository
    private let settingsStore: any DrainAlertSettingsStore
    private let notifier: (any DrainAlertNotifier)?
    private let powerState: PowerState
    private let configuration: Configuration
    private let sleep: Sleeper
    private let now: Clock
    private let reportError: ErrorReporter

    private var settings: DrainAlertSettings
    private var detailed = false
    private var previous: ProcessSnapshot?
    private var intervals: [UsageInterval] = []
    private var accumulator = UsageHourAccumulator()
    private var latest: EnergyStatus?
    private var subscribers: [UUID: AsyncStream<EnergyStatus>.Continuation] = [:]
    private var samplingTask: Task<Void, Never>?
    private var lastSampleTask: Task<EnergyStatus?, Never>?
    private var notifiedAt: [String: Date] = [:]
    private var lastPruneDate: Date?
    private var historyIssue: AppError?

    public init(
        source: any ProcessSnapshotSource,
        history: any AppUsageHistoryRepository,
        settingsStore: any DrainAlertSettingsStore,
        notifier: (any DrainAlertNotifier)? = nil,
        powerState: @escaping PowerState = { nil },
        configuration: Configuration = Configuration(),
        sleep: @escaping Sleeper = { try await Task.sleep(for: $0) },
        now: @escaping Clock = { Date() },
        reportError: @escaping ErrorReporter = { _ in }
    ) {
        self.source = source
        self.historyStore = history
        self.settingsStore = settingsStore
        self.notifier = notifier
        self.powerState = powerState
        self.configuration = configuration
        self.sleep = sleep
        self.now = now
        self.reportError = reportError
        settings = settingsStore.load()
        if !configuration.historyIsPersistent {
            historyIssue = AppError(
                kind: .io,
                userMessage: "App usage history can't be saved on this Mac, so trends will be lost when MacPulse quits."
            )
        }
    }

    // MARK: EnergyMonitoring

    public func start() {
        guard samplingTask == nil else { return }
        startLoop()
    }

    public func stop() {
        samplingTask?.cancel()
        samplingTask = nil
    }

    public func setDetailedSampling(_ enabled: Bool) {
        guard enabled != detailed else { return }
        detailed = enabled
        // Restart the loop so a long background sleep doesn't delay the faster rate.
        if samplingTask != nil {
            samplingTask?.cancel()
            startLoop()
        }
    }

    public func updates() -> AsyncStream<EnergyStatus> {
        let (stream, continuation) = AsyncStream.makeStream(of: EnergyStatus.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        subscribers[id] = continuation
        if let latest {
            continuation.yield(latest)
        }
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        return stream
    }

    public func usageHistory(since date: Date) async throws -> [AppUsageRecord] {
        let stored = try await historyStore.records(from: date, to: now())
        let pending = accumulator.pending().filter { $0.hourStart >= date }
        return (stored + pending).sorted { $0.hourStart < $1.hourStart }
    }

    public func alertSettings() -> DrainAlertSettings {
        settings
    }

    @discardableResult
    public func updateAlertSettings(_ newSettings: DrainAlertSettings) async -> Bool {
        var accepted = newSettings
        var allowed = true
        if newSettings.sendsNotifications && !settings.sendsNotifications {
            allowed = await notifier?.requestAuthorization() ?? false
            accepted.sendsNotifications = allowed
        }
        settings = accepted
        settingsStore.save(accepted)
        return allowed
    }

    public func clearHistory() async throws {
        try await historyStore.deleteAll()
        accumulator = UsageHourAccumulator()
    }

    // MARK: Test hooks

    public var latestStatus: EnergyStatus? { latest }
    public var isDetailedSampling: Bool { detailed }
    public var subscriberCount: Int { subscribers.count }

    /// Takes a sample after any sample in progress has finished.
    @discardableResult
    public func refresh() async -> EnergyStatus? {
        let previousTask = lastSampleTask
        let task = Task {
            _ = await previousTask?.value
            return await self.performSample()
        }
        lastSampleTask = task
        return await task.value
    }

    // MARK: Sampling

    private var currentInterval: Duration {
        detailed ? configuration.detailedInterval : configuration.backgroundInterval
    }

    private func startLoop() {
        let interval = currentInterval
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                _ = await self?.refresh()
                guard let self else { return }
                do {
                    try await self.sleep(interval)
                } catch {
                    return
                }
            }
        }
    }

    private func performSample() async -> EnergyStatus? {
        let timestamp = now()
        let snapshot = await source.snapshot(at: timestamp)
        defer { self.previous = snapshot }
        guard let previous else { return nil }  // first pass only establishes a baseline

        let elapsed = snapshot.timestamp.timeIntervalSince(previous.timestamp)
        // After sleep or a long pause, activity would be averaged over time MacPulse
        // didn't see. Start a fresh baseline instead.
        let maximumGap = max(180, 3 * Double(configuration.backgroundInterval.components.seconds))
        guard elapsed > 0, elapsed <= maximumGap else { return nil }

        let activities = ProcessActivityCalculator.activity(from: previous, to: snapshot)
        let apps = AppUsageAggregator.aggregate(
            activities,
            displayNames: snapshot.appDisplayNames,
            excludingPID: snapshot.ownPID,
            thresholds: configuration.thresholds
        )
        let onBattery = await powerState()
        let interval = UsageInterval(start: previous.timestamp, end: snapshot.timestamp, onBattery: onBattery, apps: apps)

        intervals.append(interval)
        let keepFrom = timestamp.addingTimeInterval(-configuration.inMemoryWindow)
        intervals.removeAll { $0.end < keepFrom }

        await persist(accumulator.add(interval))
        await pruneIfDue(at: timestamp)

        let recentFrom = timestamp.addingTimeInterval(-configuration.recentWindow)
        let recent = AppUsageAggregator.average(intervals.filter { $0.end > recentFrom }, thresholds: configuration.thresholds)

        let own = activities.first { $0.identity.pid == snapshot.ownPID }
        let ownCPU: Metric<Double> = own.map { .measured($0.cpuPercent) } ?? .unavailable(.notYetSampled)
        let busy = ProcessActivityCalculator.systemBusyFraction(from: previous.systemCPU, to: snapshot.systemCPU)
        let systemCPU: Metric<Double> = busy.map { .measured($0 * 100) } ?? .unavailable(.notSupportedOnThisMac)

        let alerts = DrainAlertEvaluator.alerts(for: intervals, settings: settings, now: timestamp)
        await notify(alerts, at: timestamp)

        let status = EnergyStatus(
            timestamp: timestamp,
            intervalSeconds: elapsed,
            current: apps,
            recent: recent,
            recentWindowMinutes: Int(configuration.recentWindow / 60),
            systemCPUPercent: systemCPU,
            energyDataAvailable: apps.contains { $0.energyMilliwatts != nil },
            unreadableProcessCount: snapshot.unreadableProcessCount,
            ownCPUPercent: ownCPU,
            onBattery: onBattery,
            alerts: alerts,
            historyIssue: historyIssue
        )
        publish(status)
        return status
    }

    private func persist(_ records: [AppUsageRecord]) async {
        guard !records.isEmpty else { return }
        do {
            try await historyStore.append(records)
            if configuration.historyIsPersistent { historyIssue = nil }
        } catch {
            fail(AppError.wrapping(error, userMessage: "Couldn't save app usage history."))
        }
    }

    private func pruneIfDue(at timestamp: Date) async {
        if let lastPruneDate, timestamp.timeIntervalSince(lastPruneDate) < 24 * 60 * 60 { return }
        lastPruneDate = timestamp
        do {
            try await historyStore.prune(olderThan: timestamp.addingTimeInterval(-configuration.historyRetention))
        } catch {
            fail(AppError.wrapping(error, userMessage: "Couldn't remove old app usage history."))
        }
    }

    private func notify(_ alerts: [DrainAlert], at timestamp: Date) async {
        guard settings.sendsNotifications, let notifier else { return }
        for alert in alerts {
            if let last = notifiedAt[alert.appKey], timestamp.timeIntervalSince(last) < configuration.notificationCooldown {
                continue
            }
            notifiedAt[alert.appKey] = timestamp
            await notifier.post(alert)
        }
    }

    private func fail(_ error: AppError) {
        historyIssue = error
        reportError(error)
    }

    private func publish(_ status: EnergyStatus) {
        if let latest, latest.timestamp > status.timestamp { return }
        latest = status
        for continuation in subscribers.values {
            continuation.yield(status)
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }
}
