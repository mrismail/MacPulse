import Foundation

/// Samples the battery periodically and on power-source changes, records history,
/// computes runtime estimates and broadcasts `BatteryStatus` to subscribers.
///
/// Energy use: one IOKit read plus one small file append per sample. The default
/// interval is 60 s and the sleeper is expected to allow timer tolerance so macOS can
/// coalesce wake-ups.
public actor BatteryMonitor: BatteryMonitoring {
    public struct Configuration: Sendable {
        public var samplingInterval: Duration
        public var historyRetention: TimeInterval
        public var estimatorParameters: RuntimeEstimator.Parameters

        public init(
            samplingInterval: Duration = .seconds(60),
            historyRetention: TimeInterval = 30 * 24 * 60 * 60,
            estimatorParameters: RuntimeEstimator.Parameters = RuntimeEstimator.Parameters()
        ) {
            self.samplingInterval = samplingInterval
            self.historyRetention = historyRetention
            self.estimatorParameters = estimatorParameters
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
    private let now: Clock
    private let reportError: ErrorReporter

    private var latest: BatteryStatus?
    private var subscribers: [UUID: AsyncStream<BatteryStatus>.Continuation] = [:]
    private var samplingTask: Task<Void, Never>?
    private var eventsTask: Task<Void, Never>?
    private var lastSampleDate: Date?

    /// Power-source notifications can arrive in bursts; samples closer together than
    /// this are skipped.
    static let minimumEventSpacing: TimeInterval = 5

    public init(
        source: any BatteryReadingSource,
        history: any BatteryHistoryRepository,
        powerEvents: (any PowerSourceEventSource)? = nil,
        configuration: Configuration = Configuration(),
        sleep: @escaping Sleeper = { try await Task.sleep(for: $0) },
        now: @escaping Clock = { Date() },
        reportError: @escaping ErrorReporter = { _ in }
    ) {
        self.source = source
        self.historyStore = history
        self.powerEvents = powerEvents
        self.configuration = configuration
        self.sleep = sleep
        self.now = now
        self.reportError = reportError
    }

    // MARK: BatteryMonitoring

    public func start() {
        guard samplingTask == nil else { return }
        samplingTask = Task { [weak self] in
            await self?.pruneHistory()
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
                    await self?.sampleAfterPowerEvent()
                }
            }
        }
    }

    public func stop() {
        samplingTask?.cancel()
        eventsTask?.cancel()
        samplingTask = nil
        eventsTask = nil
    }

    public func refresh() async {
        await sample()
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
        // Re-sample so the estimate no longer relies on deleted history.
        await sample()
    }

    // MARK: Internals

    /// Number of active subscribers. Exposed for tests.
    public var subscriberCount: Int { subscribers.count }

    /// The most recent status. Exposed for tests.
    public var latestStatus: BatteryStatus? { latest }

    func sampleAfterPowerEvent() async {
        if let lastSampleDate, now().timeIntervalSince(lastSampleDate) < Self.minimumEventSpacing {
            return
        }
        await sample()
    }

    @discardableResult
    func sample() async -> BatteryStatus {
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

        let windowStart = timestamp.addingTimeInterval(-configuration.estimatorParameters.window)
        var recent: [BatterySnapshot] = []
        do {
            recent = try await historyStore.snapshots(from: windowStart, to: timestamp)
        } catch {
            reportError(AppError.wrapping(error, userMessage: "Couldn't read battery history."))
        }

        let provisional = BatterySnapshot(reading: reading, estimatedRuntimeMinutes: nil)
        let estimate: RuntimeEstimator.Estimate
        if reading.powerSource.value == .battery {
            estimate = RuntimeEstimator.estimate(
                from: recent + [provisional],
                now: timestamp,
                parameters: configuration.estimatorParameters
            )
        } else {
            let notOnBattery = Metric<Int>.unavailable(.notApplicable("Connected to power."))
            estimate = RuntimeEstimator.Estimate(
                runtime: notOnBattery,
                ratePercentPerHour: .unavailable(.notApplicable("Connected to power."))
            )
        }

        let status = BatteryStatus(
            reading: reading,
            runtimeFromRecentDischarge: estimate.runtime,
            dischargeRatePercentPerHour: estimate.ratePercentPerHour
        )

        do {
            try await historyStore.append(
                BatterySnapshot(reading: reading, estimatedRuntimeMinutes: status.bestRuntimeEstimate.value)
            )
        } catch {
            reportError(AppError.wrapping(error, userMessage: "Couldn't save battery history."))
        }

        publish(status)
        return status
    }

    private func publish(_ status: BatteryStatus) {
        latest = status
        for continuation in subscribers.values {
            continuation.yield(status)
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }

    private func pruneHistory() async {
        do {
            try await historyStore.prune(olderThan: now().addingTimeInterval(-configuration.historyRetention))
        } catch {
            reportError(AppError.wrapping(error, userMessage: "Couldn't remove old battery history."))
        }
    }
}
