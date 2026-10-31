import MacPulseDomain
import MacPulseShared
import Observation

@MainActor
@Observable
public final class OverviewViewModel {
    public private(set) var systemInfo: LoadState<SystemInfo> = .idle

    // Filled in by later phases. Shown as "Unavailable" so the dashboard
    // never displays a made-up number.
    public private(set) var batteryCharge: Metric<Double> = .unavailable(.notYetImplemented)
    public private(set) var estimatedRuntimeMinutes: Metric<Int> = .unavailable(.notYetImplemented)
    public private(set) var storageAvailableBytes: Metric<UInt64> = .unavailable(.notYetImplemented)
    public private(set) var reclaimableBytes: Metric<UInt64> = .unavailable(.notYetImplemented)

    public let upcomingFeatures: [PlannedFeature] = PlannedFeature.all

    @ObservationIgnored private let systemInfoRepository: any SystemInfoRepository

    public init(systemInfoRepository: any SystemInfoRepository) {
        self.systemInfoRepository = systemInfoRepository
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
