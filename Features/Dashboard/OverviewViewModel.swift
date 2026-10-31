import MacPulseDomain
import MacPulseShared
import Observation

@MainActor
@Observable
public final class OverviewViewModel {
    public private(set) var systemInfo: LoadState<SystemInfo> = .idle

    public private(set) var batteryCharge: Metric<Double> = .unavailable(.notYetSampled)
    public private(set) var estimatedRuntimeMinutes: Metric<Int> = .unavailable(.notYetSampled)
    public private(set) var batteryStateDescription: String?

    // Filled in by later phases. Shown as "Unavailable" so the dashboard
    // never displays a made-up number.
    public private(set) var storageAvailableBytes: Metric<UInt64> = .unavailable(.notYetImplemented)
    public private(set) var reclaimableBytes: Metric<UInt64> = .unavailable(.notYetImplemented)

    public let upcomingFeatures: [PlannedFeature] = PlannedFeature.all

    @ObservationIgnored private let systemInfoRepository: any SystemInfoRepository
    @ObservationIgnored private let batteryMonitor: any BatteryMonitoring

    public init(systemInfoRepository: any SystemInfoRepository, batteryMonitor: any BatteryMonitoring) {
        self.systemInfoRepository = systemInfoRepository
        self.batteryMonitor = batteryMonitor
    }

    /// Follows battery updates until the calling task is cancelled.
    public func observeBattery() async {
        for await status in await batteryMonitor.updates() {
            apply(status)
        }
    }

    func apply(_ status: BatteryStatus) {
        batteryCharge = status.reading.charge
        estimatedRuntimeMinutes = status.reading.powerSource.value == .battery
            ? status.bestRuntimeEstimate
            : status.reading.systemTimeToEmptyMinutes
        guard status.reading.hasBattery else {
            batteryStateDescription = "This Mac has no battery"
            return
        }
        batteryStateDescription = switch status.reading.chargingState.value {
        case .charging: "Charging"
        case .discharging: "On battery"
        case .notCharging: "Plugged in, not charging"
        case .fullyCharged: "Fully charged"
        case nil: nil
        }
    }

    /// Loads data for the dashboard. Safe to call repeatedly; concurrent calls are ignored.
    public func load() async {
        guard !systemInfo.isLoading else { return }
        systemInfo = .loading
        do {
            let info = try await systemInfoRepository.currentSystemInfo()
            systemInfo = .loaded(info)
        } catch {
            let appError = AppError.wrapping(error, userMessage: "Couldn't read information about this Mac.")
            Log.logger(.system).error("Overview system info failed: \(appError.description, privacy: .public)")
            systemInfo = .failed(appError)
        }
    }
}
