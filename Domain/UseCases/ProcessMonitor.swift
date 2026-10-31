import Foundation

/// Samples the current user's processes, computes per-app activity and estimated
/// battery impact, keeps a recent window in memory, persists hourly usage, evaluates
/// drain alerts and broadcasts `EnergyStatus`.
///
/// Energy use: one pass over the user's processes every 60 s in the background, or
/// every 10 s while a live Energy view is visible. MacPulse reports its own CPU use in
/// every status so the overhead is visible.
///
/// Guarantees (Phase 3 review):
/// - The impact basis (energy vs CPU) is chosen once per session: energy as soon as macOS
///   has reported any per-app energy, never switching back.
/// - Sleep is detected by comparing awake uptime with wall time; intervals across sleep,
///   shorter than `minimumInterval`, or from an empty process table are skipped.
/// - The hour in progress is saved every `pendingPersistInterval` and on `flush()`, and
///   reloaded after a relaunch, so trends survive quitting.
public actor ProcessMonitor: EnergyMonitoring {
    public struct Configuration: Sendable {
        public static let defaultHistoryRetentionDays = 7

        public var backgroundInterval: Duration = .seconds(60)
        public var detailedInterval: Duration = .seconds(10)
        /// Intervals shorter than this are too noisy for CPU percentages.
        public var minimumInterval: TimeInterval = 2
        /// Wall time exceeding awake time by more than this means the Mac slept.
        public var sleepTolerance: TimeInterval = 5
        /// Without uptime data, gaps longer than this are treated as sleep.
        public var maximumGapWithoutUptime: TimeInterval = 180
        public var recentWindow: TimeInterval = 10 * 60
        /// How much interval history to keep in memory (also bounds alert windows).
        public var inMemoryWindow: TimeInterval = 60 * 60
        public var historyRetention: TimeInterval = TimeInterval(defaultHistoryRetentionDays) * 24 * 60 * 60
        /// How often the hour in progress is saved.
        public var pendingPersistInterval: TimeInterval = 5 * 60
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
    /// What the most recent settings update asked for, for the notification switch.
    private var notificationsRequested = false
    /// Number of live views that asked for detailed sampling.
    private var detailedRequests = 0
    private var previous: ProcessSnapshot?
    private var intervals: [UsageInterval] = []
    private var accumulator = UsageHourAccumulator()
    private var accumulatorSeeded = false
    private var lastPendingPersist: Date?
    private var energyAccountingSeen = false
    private var historyVersion = 0
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
                userMessage: String(localized: "App usage history can't be saved on this Mac, so trends will be lost when MacPulse quits.")
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

    /// Detailed sampling is reference-counted: it stays on while any view still wants it,
    /// so overlapping views (fast navigation) can't switch it off for a visible screen.
    public func setDetailedSampling(_ enabled: Bool) {
        let wasDetailed = isDetailedSampling
        detailedRequests = max(0, detailedRequests + (enabled ? 1 : -1))
        guard isDetailedSampling != wasDetailed, samplingTask != nil else { return }
        // Restart so a long background sleep doesn't delay the faster rate. The first
        // sample of the new loop waits one interval, so no millisecond-long interval.
        samplingTask?.cancel()
        startLoop(sampleImmediately: false)
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
        return AppUsageRecord.latestPerAppAndHour(stored + pending)
    }

    public func alertSettings() -> DrainAlertSettings {
        settings
    }

    @discardableResult
    public func updateAlertSettings(_ newSettings: DrainAlertSettings) async -> Bool {
        notificationsRequested = newSettings.sendsNotifications
        let turningOnNotifications = newSettings.sendsNotifications && !settings.sendsNotifications
        // Apply everything except a not-yet-allowed notification switch immediately, so an
        // edit made while the permission prompt is open is never overwritten.
        var applied = newSettings
        if turningOnNotifications {
            applied.sendsNotifications = false
        }
        apply(applied)
        guard turningOnNotifications else { return true }

        let allowed = await notifier?.requestAuthorization() ?? false
        guard allowed else { return false }
        // Merge only the notification switch into the latest settings, and only if the
        // latest request still wants notifications.
        if notificationsRequested {
            var current = settings
            current.sendsNotifications = true
            apply(current)
        }
        return true
    }

    public func clearHistory() async throws {
        // Reset memory first and wait for any sample in progress, so nothing from before
        // the clear can be written back afterwards.
        accumulator = UsageHourAccumulator()
        accumulatorSeeded = true
        intervals.removeAll()
        _ = await lastSampleTask?.value
        accumulator = UsageHourAccumulator()
        try await historyStore.deleteAll()
        historyVersion += 1
        if let latest {
            publish(latest.withHistoryVersion(historyVersion), force: true)
        }
    }

    /// Saves the hour in progress (call when the app quits or the Mac goes to sleep).
    public func flush() async {
        await persist(accumulator.pending())
    }

    // MARK: Test hooks

    public var latestStatus: EnergyStatus? { latest }
    public var isDetailedSampling: Bool { detailedRequests > 0 }
    public var subscriberCount: Int { subscribers.count }
    public var inMemoryIntervalCount: Int { intervals.count }

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
        isDetailedSampling ? configuration.detailedInterval : configuration.backgroundInterval
    }

    private func startLoop(sampleImmediately: Bool = true) {
        let interval = currentInterval
        samplingTask = Task { [weak self] in
            if !sampleImmediately {
                guard let self else { return }
                do { try await self.sleep(interval) } catch { return }
            }
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

    private func apply(_ newSettings: DrainAlertSettings) {
        settings = newSettings
        settingsStore.save(newSettings)
    }

    private func performSample() async -> EnergyStatus? {
        let timestamp = now()
        let snapshot = await source.snapshot(at: timestamp)

        // An empty table means the read failed (e.g. the process table grew between
        // calls); keep the old baseline rather than treating every process as new.
        guard !snapshot.processes.isEmpty else { return nil }
        await seedAccumulatorIfNeeded(at: timestamp)

        guard let previous else {
            self.previous = snapshot  // first pass only establishes a baseline
            return nil
        }
        let elapsed = snapshot.timestamp.timeIntervalSince(previous.timestamp)
        // Too short to be meaningful: keep the old baseline and wait for more time.
        guard elapsed >= configuration.minimumInterval else { return nil }
        self.previous = snapshot
        guard !sleptBetween(previous, snapshot, elapsed: elapsed) else { return nil }

        let activities = ProcessActivityCalculator.activity(from: previous, to: snapshot)
        if !energyAccountingSeen, activities.contains(where: { ($0.energyMilliwatts ?? 0) > 0 }) {
            energyAccountingSeen = true
        }
        let basis: AppUsageAggregator.ImpactBasis = energyAccountingSeen ? .energy : .cpu
        let apps = AppUsageAggregator.aggregate(
            activities,
            displayNames: snapshot.appDisplayNames,
            excludingPID: snapshot.ownPID,
            basis: basis,
            thresholds: configuration.thresholds
        )
        let onBattery = await powerState()
        let interval = UsageInterval(start: previous.timestamp, end: snapshot.timestamp, onBattery: onBattery, apps: apps)

        intervals.append(interval)
        let keepFrom = timestamp.addingTimeInterval(-configuration.inMemoryWindow)
        intervals.removeAll { $0.end < keepFrom }

        await persist(accumulator.add(interval))
        let pendingIsStale = lastPendingPersist.map {
            timestamp.timeIntervalSince($0) >= configuration.pendingPersistInterval
        } ?? true
        if pendingIsStale {
            lastPendingPersist = timestamp
            await persist(accumulator.pending())
        }
        await pruneIfDue(at: timestamp)

        let recentFrom = timestamp.addingTimeInterval(-configuration.recentWindow)
        let recent = AppUsageAggregator.average(
            intervals.filter { $0.end > recentFrom },
            basis: basis,
            thresholds: configuration.thresholds
        )

        let own = activities.first { $0.identity.pid == snapshot.ownPID }
        let ownCPU: Metric<Double> = own.map { .measured($0.cpuPercent) } ?? .unavailable(.notYetSampled)
        let busy = ProcessActivityCalculator.systemBusyFraction(from: previous.systemCPU, to: snapshot.systemCPU)
        let systemCPU: Metric<Double> = busy.map { .measured($0 * 100) } ?? .unavailable(.notSupportedOnThisMac)
        let pressure: Metric<MemoryPressureLevel> = snapshot.memoryPressure.map { .measured($0) }
            ?? .unavailable(.notSupportedOnThisMac)

        let alerts = DrainAlertEvaluator.alerts(for: intervals, settings: settings, now: timestamp)
        await notify(alerts, at: timestamp)

        let status = EnergyStatus(
            timestamp: timestamp,
            intervalSeconds: elapsed,
            current: apps,
            recent: recent,
            recentWindowMinutes: Int(configuration.recentWindow / 60),
            systemCPUPercent: systemCPU,
            memoryPressure: pressure,
            energyDataAvailable: energyAccountingSeen,
            unreadableProcessCount: snapshot.unreadableProcessCount,
            ownCPUPercent: ownCPU,
            onBattery: onBattery,
            alerts: alerts,
            historyIssue: historyIssue,
            historyVersion: historyVersion
        )
        publish(status)
        return status
    }

    /// `true` when the Mac slept between the two snapshots.
    func sleptBetween(_ previous: ProcessSnapshot, _ current: ProcessSnapshot, elapsed: TimeInterval) -> Bool {
        if let before = previous.awakeUptime, let after = current.awakeUptime {
            let awake = after - before
            return awake < 0 || elapsed - awake > configuration.sleepTolerance
        }
        return elapsed > configuration.maximumGapWithoutUptime
    }

    private func seedAccumulatorIfNeeded(at timestamp: Date) async {
        guard !accumulatorSeeded else { return }
        accumulatorSeeded = true
        let hourStart = Calendar.current.dateInterval(of: .hour, for: timestamp)?.start ?? timestamp
        do {
            let saved = try await historyStore.records(from: hourStart, to: timestamp)
            accumulator.seed(with: saved, at: timestamp)
        } catch {
            fail(AppError.wrapping(error, userMessage: String(localized: "Couldn't read app usage history.")))
        }
    }

    private func persist(_ records: [AppUsageRecord]) async {
        guard !records.isEmpty else { return }
        do {
            try await historyStore.append(records)
            if configuration.historyIsPersistent { historyIssue = nil }
        } catch {
            fail(AppError.wrapping(error, userMessage: String(localized: "Couldn't save app usage history.")))
        }
    }

    private func pruneIfDue(at timestamp: Date) async {
        if let lastPruneDate, timestamp.timeIntervalSince(lastPruneDate) < 24 * 60 * 60 { return }
        lastPruneDate = timestamp
        do {
            try await historyStore.prune(olderThan: timestamp.addingTimeInterval(-configuration.historyRetention))
        } catch {
            fail(AppError.wrapping(error, userMessage: String(localized: "Couldn't remove old app usage history.")))
        }
        notifiedAt = notifiedAt.filter { timestamp.timeIntervalSince($0.value) < configuration.notificationCooldown }
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

    private func publish(_ status: EnergyStatus, force: Bool = false) {
        if !force, let latest, latest.timestamp > status.timestamp { return }
        latest = status
        for continuation in subscribers.values {
            continuation.yield(status)
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }
}
