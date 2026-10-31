import MacPulseDomain
import MacPulseShared
import Observation

@MainActor
@Observable
public final class OverviewViewModel {
    public private(set) var systemInfo: LoadState<SystemInfo> = .idle

    public private(set) var batteryStatus: BatteryStatus?
    public private(set) var recommendations: [Recommendation] = []

    public var batteryCharge: Metric<Double> {
        batteryStatus?.reading.charge ?? .unavailable(.notYetSampled)
    }

    /// Same definition as the Battery screen's "Estimated runtime".
    public var estimatedRuntimeMinutes: Metric<Int> {
        BatteryStatusPresentation.estimatedRuntime(batteryStatus)
    }

    public var batteryStateDescription: String? {
        batteryStatus.map { BatteryStatusPresentation.stateDescription($0.reading) }
    }

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
        batteryStatus = status
        recommendations = BatteryRecommendations.make(for: status)
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
            Log.logger(.system).log(appError, context: "Overview system info")
            systemInfo = .failed(appError)
        }
    }
}
