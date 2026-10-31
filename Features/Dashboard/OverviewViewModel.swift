import MacPulseDomain
import MacPulseShared
import Observation

@MainActor
@Observable
public final class OverviewViewModel {
    public private(set) var systemInfo: LoadState<SystemInfo> = .idle

    public private(set) var batteryStatus: BatteryStatus?
    public private(set) var energyStatus: EnergyStatus?
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
    @ObservationIgnored private let energyMonitor: (any EnergyMonitoring)?

    public init(
        systemInfoRepository: any SystemInfoRepository,
        batteryMonitor: any BatteryMonitoring,
        energyMonitor: (any EnergyMonitoring)? = nil
    ) {
        self.systemInfoRepository = systemInfoRepository
        self.batteryMonitor = batteryMonitor
        self.energyMonitor = energyMonitor
    }

    /// Follows app activity until the calling task is cancelled.
    public func observeEnergy() async {
        guard let energyMonitor else { return }
        for await status in await energyMonitor.updates() {
            energyStatus = status
            rebuildRecommendations()
        }
    }

    /// The apps with the highest estimated battery impact recently.
    public var topApps: [AppUsage] {
        Array((energyStatus?.recent ?? []).prefix(3))
    }

    /// Follows battery updates until the calling task is cancelled.
    public func observeBattery() async {
        for await status in await batteryMonitor.updates() {
            apply(status)
        }
    }

    func apply(_ status: BatteryStatus) {
        batteryStatus = status
        rebuildRecommendations()
    }

    private func rebuildRecommendations() {
        let drain = (energyStatus?.alerts ?? []).map { alert in
            Recommendation(
                id: "drain-\(alert.appKey)",
                title: String(localized: "\(alert.displayName) is using a lot of CPU"),
                detail: alert.explanation,
                severity: .warning
            )
        }
        recommendations = (drain + BatteryRecommendations.make(for: batteryStatus))
            .sorted { $0.severity > $1.severity }
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
