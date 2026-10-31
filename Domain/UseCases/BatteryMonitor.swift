import Foundation

/// Samples the battery periodically and on power-source changes, records history,
/// computes runtime estimates and broadcasts `BatteryStatus` to subscribers.
///
/// Guarantees:
/// - Samples never overlap: each one starts after the previous finished, so estimates
///   always include the previous sample and published statuses are in time order.
/// - A power-source change always produces a sample taken *after* the change, even when
///   it arrives right after a timer sample (a trailing sample is scheduled).
/// - The recent window used for the runtime estimate is kept in memory; the history
///   store is read once at startup, not on every sample.
///
/// Energy use: one IOKit read plus one small file append per sample. The default
/// interval is 60 s and the live sleeper uses timer tolerance so macOS can coalesce
/// wake-ups.
public actor BatteryMonitor: BatteryMonitoring {
    public struct Configuration: Sendable {
        public static let defaultHistoryRetentionDays = 30

        public var samplingInterval: Duration
        public var historyRetention: TimeInterval
        public var pruneInterval: TimeInterval
        public var estimatorParameters: RuntimeEstimator.Parameters
        /// Power-source notifications closer together than this are coalesced into one
        /// trailing sample.
        public var minimumEventSpacing: TimeInterval
        /// `false` when history is only kept in memory (the on-disk store failed).
        public var historyIsPersistent: Bool

        public init(
            samplingInterval: Duration = .seconds(60),
            historyRetention: TimeInterval = TimeInterval(defaultHistoryRetentionDays) * 24 * 60 * 60,
            pruneInterval: TimeInterval = 24 * 60 * 60,
            estimatorParameters: RuntimeEstimator.Parameters = RuntimeEstimator.Parameters(),
            minimumEventSpacing: TimeInterval = 5,
            historyIsPersistent: Bool = true
        ) {
            self.samplingInterval = samplingInterval
            self.historyRetention = historyRetention
            self.pruneInterval = pruneInterval
            self.estimatorParameters = estimatorParameters
            self.minimumEventSpacing = minimumEventSpacing
            self.historyIsPersistent = historyIsPersistent
        }
    }

    public typealias Sleeper = @Sendable (Duration) async throws -> Void
    public typealias Clock = @Sendable () -> Date
    public typealias ErrorReporter = @Sendable (AppError) -> Void

    private let source: any BatteryReadingSource
    private let historyStore: any BatteryHistoryRepository
    private let powerEvents: (any PowerSourceEventSource)?
    private let configuration: Configuration
    private let sleep: Sleeper
    private let eventDelay: Sleeper
    private let now: Clock
    private let reportError: ErrorReporter

    private var latest: BatteryStatus?
    private var subscribers: [UUID: AsyncStream<BatteryStatus>.Continuation] = [:]
    private var samplingTask: Task<Void, Never>?
    private var eventsTask: Task<Void, Never>?
    private var trailingEventTask: Task<Void, Never>?
    /// Tail of the sample queue; each new sample waits for it.
    private var lastSampleTask: Task<BatteryStatus, Never>?
    private var lastSampleDate: Date?
    private var lastPruneDate: Date?
    /// On-battery-relevant samples inside the estimator window, oldest first.
    private var recentWindow: [BatterySnapshot] = []
    private var recentWindowLoaded = false
    private var historyIssue: AppError?

    public init(
        source: any BatteryReadingSource,
        history: any BatteryHistoryRepository,
        powerEvents: (any PowerSourceEventSource)? = nil,
        configuration: Configuration = Configuration(),
        sleep: @escaping Sleeper = { try await Task.sleep(for: $0) },
        eventDelay: @escaping Sleeper = { try await Task.sleep(for: $0) },
        now: @escaping Clock = { Date() },
        reportError: @escaping ErrorReporter = { _ in }
    ) {
        self.source = source
        self.historyStore = history
        self.powerEvents = powerEvents
        self.configuration = configuration
        self.sleep = sleep
        self.eventDelay = eventDelay
        self.now = now
        self.reportError = reportError
        if !configuration.historyIsPersistent {
            historyIssue = AppError(
                kind: .io,
                userMessage: "Battery history can't be saved on this Mac, so it will be lost when MacPulse quits."
            )
        }
    }

    // MARK: BatteryMonitoring

    public func start() {
        guard samplingTask == nil else { return }
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                _ = await self?.sample()
                guard let self else { return }
                do {
                    try await self.sleep(self.configuration.samplingInterval)
                } catch {
                    return  // cancelled
                }
            }
        }
        if let powerEvents {
            eventsTask = Task { [weak self] in
                for await _ in powerEvents.events() {
                    await self?.handlePowerEvent()
                }
            }
        }
    }

    public func stop() {
        samplingTask?.cancel()
        eventsTask?.cancel()
        trailingEventTask?.cancel()
        samplingTask = nil
        eventsTask = nil
        trailingEventTask = nil
    }

    public func refresh() async {
        _ = await sample()
    }

    public func updates() -> AsyncStream<BatteryStatus> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: BatteryStatus.self,
            bufferingPolicy: .bufferingNewest(1)
        )
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

    public func history(since date: Date) async throws -> [BatterySnapshot] {
        try await historyStore.snapshots(from: date, to: now())
    }

    public func clearHistory() async throws {
        try await historyStore.deleteAll()
        recentWindow.removeAll()
        // Re-sample so the estimate no longer relies on deleted history.
        _ = await sample()
    }

    // MARK: Test hooks

    /// Number of active subscribers.
    public var subscriberCount: Int { subscribers.count }

    /// The most recent status.
    public var latestStatus: BatteryStatus? { latest }

    // MARK: Sampling

    /// Takes a sample after any sample already in progress has finished.
    @discardableResult
    func sample() async -> BatteryStatus {
        let previous = lastSampleTask
        let task = Task {
            _ = await previous?.value
            return await self.performSample()
        }
        lastSampleTask = task
        return await task.value
    }

    func handlePowerEvent() async {
        guard let lastSampleDate else {
            _ = await sample()
            return
        }
        let elapsed = now().timeIntervalSince(lastSampleDate)
        if elapsed >= configuration.minimumEventSpacing {
            _ = await sample()
            return
        }
        // Too soon after the last sample: make sure one more sample follows the burst.
        guard trailingEventTask == nil else { return }
        let wait = configuration.minimumEventSpacing - elapsed
        trailingEventTask = Task {
            do {
                try await self.eventDelay(.milliseconds(Int((wait * 1_000).rounded(.up))))
            } catch {
                await self.clearTrailingEventTask()
                return
            }
            await self.clearTrailingEventTask()
            _ = await self.sample()
        }
    }

    private func clearTrailingEventTask() async {
        trailingEventTask = nil
    }

    private func performSample() async -> BatteryStatus {
        let timestamp = now()
        lastSampleDate = timestamp
        let reading = await source.currentReading(at: timestamp)

        guard reading.hasBattery else {
            let unsupported = UnavailabilityReason.notSupportedOnThisMac
            let status = BatteryStatus(
                reading: reading,
                runtimeFromRecentDischarge: .unavailable(unsupported),
                dischargeRatePercentPerHour: .unavailable(unsupported)
            )
            publish(status)
            return status
        }

        await loadRecentWindowIfNeeded(at: timestamp)
        let windowStart = timestamp.addingTimeInterval(-configuration.estimatorParameters.window)
        recentWindow.removeAll { $0.timestamp < windowStart }

        let estimate: RuntimeEstimator.Estimate
        if reading.powerSource.value == .battery {
            let provisional = BatterySnapshot(reading: reading, estimatedRuntimeMinutes: nil)
            estimate = RuntimeEstimator.estimate(
                from: recentWindow + [provisional],
                now: timestamp,
                parameters: configuration.estimatorParameters
            )
        } else {
            let connected = UnavailabilityReason.notApplicable("Connected to power.")
            estimate = RuntimeEstimator.Estimate(
                runtime: .unavailable(connected),
                ratePercentPerHour: .unavailable(connected)
            )
        }

        // Only MacPulse's own estimate is stored, so stored values have one meaning.
        let snapshot = BatterySnapshot(reading: reading, estimatedRuntimeMinutes: estimate.runtime.value)
        recentWindow.append(snapshot)
        do {
            try await historyStore.append(snapshot)
            if configuration.historyIsPersistent {
                historyIssue = nil
            }
        } catch {
            fail(AppError.wrapping(error, userMessage: "Couldn't save battery history."))
        }
        await pruneIfDue(at: timestamp)

        let status = BatteryStatus(
            reading: reading,
            runtimeFromRecentDischarge: estimate.runtime,
            dischargeRatePercentPerHour: estimate.ratePercentPerHour,
            historyIssue: historyIssue
        )
        publish(status)
        return status
    }

    private func loadRecentWindowIfNeeded(at timestamp: Date) async {
        guard !recentWindowLoaded else { return }
        recentWindowLoaded = true
        let windowStart = timestamp.addingTimeInterval(-configuration.estimatorParameters.window)
        do {
            recentWindow = try await historyStore.snapshots(from: windowStart, to: timestamp)
        } catch {
            fail(AppError.wrapping(error, userMessage: "Couldn't read battery history."))
        }
    }

    private func pruneIfDue(at timestamp: Date) async {
        if let lastPruneDate, timestamp.timeIntervalSince(lastPruneDate) < configuration.pruneInterval {
            return
        }
        lastPruneDate = timestamp
        do {
            try await historyStore.prune(olderThan: timestamp.addingTimeInterval(-configuration.historyRetention))
        } catch {
            fail(AppError.wrapping(error, userMessage: "Couldn't remove old battery history."))
        }
    }

    private func fail(_ error: AppError) {
        historyIssue = error
        reportError(error)
    }

    private func publish(_ status: BatteryStatus) {
        // Samples are serialized, but never let an older reading replace a newer one.
        if let latest, latest.reading.timestamp > status.reading.timestamp {
            return
        }
        latest = status
        for continuation in subscribers.values {
            continuation.yield(status)
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }
}
