import Foundation
import MacPulseDomain
import MacPulseShared
import Observation

@MainActor
@Observable
public final class BatteryViewModel {
    public private(set) var status: BatteryStatus?
    public private(set) var chartPoints: [BatteryChartPoint] = []
    public private(set) var chargingSessions: [ChargingSession] = []
    public private(set) var historyError: AppError?
    /// Selected chart range. The view reloads history when it changes.
    public var range: BatteryHistoryRange = .day

    @ObservationIgnored private let monitor: any BatteryMonitoring
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(monitor: any BatteryMonitoring, now: @escaping @Sendable () -> Date = { Date() }) {
        self.monitor = monitor
        self.now = now
    }

    /// `false` once a reading shows the Mac has no internal battery.
    public var hasBattery: Bool { status?.reading.hasBattery ?? true }

    /// Sessions that overlap the selected range, most recent first.
    public var recentSessions: [ChargingSession] {
        chargingSessions.sorted { $0.start > $1.start }
    }

    /// Follows battery updates until the calling task is cancelled (the view disappears).
    public func observe() async {
        for await status in await monitor.updates() {
            self.status = status
            await reloadHistory()
        }
    }

    public func refresh() async {
        await monitor.refresh()
    }

    public func reloadHistory() async {
        let end = now()
        do {
            let snapshots = try await monitor.history(since: end.addingTimeInterval(-range.duration))
            chartPoints = BatteryHistoryChartModel.points(from: snapshots)
            chargingSessions = ChargingSessionDetector.sessions(from: snapshots, now: end)
            historyError = nil
        } catch {
            let appError = AppError.wrapping(error, userMessage: "Couldn't load battery history.")
            Log.logger(.battery).log(appError, context: "Battery history")
            historyError = appError
        }
    }

    // MARK: Display helpers (kept here so they can be unit-tested)

    public var stateDescription: String {
        guard let reading = status?.reading else { return "Reading battery…" }
        guard reading.hasBattery else { return "No battery" }
        switch reading.chargingState.value {
        case .charging: return "Charging"
        case .discharging: return "On battery"
        case .notCharging: return "Plugged in, not charging"
        case .fullyCharged: return "Fully charged"
        case nil: return "Status unknown"
        }
    }

    public var conditionDescription: Metric<String> {
        guard let reading = status?.reading else { return .unavailable(.notYetSampled) }
        return reading.condition.map { condition in
            switch condition {
            case .normal: "Normal"
            case .serviceRecommended(let text): text
            }
        }
    }
}
