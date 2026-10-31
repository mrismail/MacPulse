import Foundation
import MacPulseDomain
import MacPulseShared
import Observation

@MainActor
@Observable
public final class BatteryViewModel {
    public private(set) var status: BatteryStatus?
    public private(set) var chartPoints: [BatteryChartPoint] = []
    /// Charging sessions in the selected range, most recent first.
    public private(set) var recentSessions: [ChargingSession] = []
    public private(set) var historyError: AppError?
    public private(set) var lastUpdated: Date?
    /// Selected chart range. The view reloads history when it changes.
    public var range: BatteryHistoryRange = .day

    /// Snapshots for the selected range, oldest first. Live updates are appended here
    /// instead of re-reading history from disk on every sample.
    @ObservationIgnored private var snapshots: [BatterySnapshot] = []
    @ObservationIgnored private var historyLoaded = false
    @ObservationIgnored private let monitor: any BatteryMonitoring
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(monitor: any BatteryMonitoring, now: @escaping @Sendable () -> Date = { Date() }) {
        self.monitor = monitor
        self.now = now
    }

    /// `false` once a reading shows the Mac has no internal battery.
    public var hasBattery: Bool { status?.reading.hasBattery ?? true }

    public var stateDescription: String { BatteryStatusPresentation.stateDescription(status?.reading) }
    public var conditionDescription: Metric<String> { BatteryStatusPresentation.condition(status?.reading) }
    public var estimatedRuntime: Metric<Int> { BatteryStatusPresentation.estimatedRuntime(status) }

    /// The x-axis domain for the chart: the full selected range ending now, so a short
    /// history isn't stretched across the whole width.
    public var chartDomain: ClosedRange<Date> {
        let end = lastUpdated ?? now()
        return end.addingTimeInterval(-range.duration)...end
    }

    /// Follows battery updates until the calling task is cancelled (the view disappears).
    public func observe() async {
        for await status in await monitor.updates() {
            apply(status)
            await appendLive(status)
        }
    }

    public func refresh() async {
        await monitor.refresh()
    }

    /// Reloads history for the selected range from disk. Results for a range that is no
    /// longer selected (the user switched while loading) are discarded.
    public func reloadHistory() async {
        let requested = range
        let end = now()
        do {
            let loaded = try await monitor.history(since: end.addingTimeInterval(-requested.duration))
            guard requested == range, !Task.isCancelled else { return }
            snapshots = loaded
            historyLoaded = true
            historyError = nil
            await rebuildDerived(at: end)
        } catch {
            guard requested == range, !Task.isCancelled else { return }
            let appError = AppError.wrapping(error, userMessage: String(localized: "Couldn't load battery history."))
            Log.logger(.battery).log(appError, context: "Battery history")
            historyError = appError
        }
    }

    // MARK: Private

    private func apply(_ status: BatteryStatus) {
        self.status = status
        lastUpdated = status.reading.timestamp
    }

    private func appendLive(_ status: BatteryStatus) async {
        guard historyLoaded, status.reading.hasBattery else { return }
        let snapshot = BatterySnapshot(reading: status.reading, estimatedRuntimeMinutes: nil)
        if let last = snapshots.last, last.timestamp >= snapshot.timestamp { return }
        snapshots.append(snapshot)
        let start = snapshot.timestamp.addingTimeInterval(-range.duration)
        snapshots.removeAll { $0.timestamp < start }
        await rebuildDerived(at: snapshot.timestamp)
    }

    private func rebuildDerived(at end: Date) async {
        let derived = await Self.derive(from: snapshots, now: end)
        chartPoints = derived.points
        recentSessions = derived.sessions
    }

    /// Runs off the main actor: downsampling and session detection over up to a week of samples.
    private nonisolated static func derive(
        from snapshots: [BatterySnapshot],
        now: Date
    ) async -> (points: [BatteryChartPoint], sessions: [ChargingSession]) {
        let points = BatteryHistoryChartModel.points(from: snapshots)
        let sessions = ChargingSessionDetector.sessions(from: snapshots, now: now).sorted { $0.start > $1.start }
        return (points, sessions)
    }
}
