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

    /// Free space on the startup disk, as the file system reports it.
    public private(set) var storageAvailableBytes: Metric<Int64> = .unavailable(.notYetSampled)
    /// Caches, logs, temporary files and Trash found by the last complete scan (estimate).
    public private(set) var reclaimableBytes: Metric<Int64> = .unavailable(.notYetSampled)
    /// The most recent scan, if any.
    public private(set) var lastScan: ScanSummary?

    public let upcomingFeatures: [PlannedFeature] = PlannedFeature.all

    @ObservationIgnored private let systemInfoRepository: any SystemInfoRepository
    @ObservationIgnored private let batteryMonitor: any BatteryMonitoring
    @ObservationIgnored private let energyMonitor: (any EnergyMonitoring)?
    @ObservationIgnored private let volumes: (any VolumeRepository)?
    @ObservationIgnored private let scanHistory: (any ScanHistoryRepository)?

    public init(
        systemInfoRepository: any SystemInfoRepository,
        batteryMonitor: any BatteryMonitoring,
        energyMonitor: (any EnergyMonitoring)? = nil,
        volumes: (any VolumeRepository)? = nil,
        scanHistory: (any ScanHistoryRepository)? = nil
    ) {
        self.systemInfoRepository = systemInfoRepository
        self.batteryMonitor = batteryMonitor
        self.energyMonitor = energyMonitor
        self.volumes = volumes
        self.scanHistory = scanHistory
    }

    /// Reads free space on the startup disk and the last scan. Called when the Overview
    /// appears, so it reflects scans made since.
    public func loadStorage() async {
        if let volumes {
            let startup = (try? await volumes.volumes())?.first { $0.kind == .startup }
            storageAvailableBytes = startup?.availableBytes ?? .unavailable(.notSupportedOnThisMac)
        }
        guard let scanHistory else { return }
        let summaries = (try? await scanHistory.summaries()) ?? []
        lastScan = ScanHistory.recent(summaries, limit: 1).first
        if let complete = ScanHistory.recent(summaries.filter(\.isComplete), limit: 1).first {
            let date = complete.finishedAt.formatted(date: .abbreviated, time: .omitted)
            reclaimableBytes = .estimated(
                complete.recoverableBytes,
                basis: String(localized: "Caches, logs, temporary files and Trash found when you scanned \(complete.rootName) on \(date).")
            )
        } else {
            reclaimableBytes = .unavailable(.notApplicable(String(localized: "Scan a folder in Space Analyzer to estimate this.")))
        }
    }

    /// Follows app activity until the calling task is cancelled.
    public func observeEnergy() async {
        guard let energyMonitor else { return }
        for await status in await energyMonitor.updates() {
            energyStatus = status
            rebuildRecommendations()
        }
    }

    /// The most active apps recently (same rule as the Battery screen).
    public var topApps: [AppUsage] {
        EnergyPresentation.topApps(energyStatus?.recent ?? [], limit: 3)
    }

    /// `true` until the first battery or energy update arrives, so the Overview doesn't
    /// claim "nothing needs attention" before it has looked.
    public var isWaitingForFirstUpdate: Bool {
        batteryStatus == nil && energyStatus == nil
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
